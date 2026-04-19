//
//  DataManager.swift
//  HospitalApp
//
//  Created by Duane Homick on 2026-01-30.
//

import Foundation
import FirebaseFirestore
import FirebaseInstallations
import FirebaseAuth

final class DataManager {
    
    // MARK: - Singleton
    static let shared = DataManager()
    private let db = Firestore.firestore()
    private var careCentersListener: ListenerRegistration?
    
    // MARK: - Properties
    private(set) var careCenters: [CareCenter] = []

    // Wait time stats cache (in-memory)
    private var waitStatsCache: [UUID: CareCenterWaitStats] = [:]
    private var lastStatsFetchAt: [UUID: Date] = [:]
    private let rateLimitKey = "waitTimeRateLimit"
    private let statsLookbackHours: Int = 4
    private let minStatsRefetchInterval: TimeInterval = 60 // 1 minute

    // Facility issues cache
    private var issuesCache: [UUID: [FacilityIssue]] = [:]
    private var lastIssuesFetchAt: [UUID: Date] = [:]
    private let minIssuesRefetchInterval: TimeInterval = 30 // seconds
    private let facilityRateLimitKey = "facilityIssueRateLimit"

    // Purge throttling
    private let lastFacilityPurgeKey = "lastFacilityIssuesPurgeAt"
    private let minPurgeInterval: TimeInterval = 60 * 60 // 1 hour

    // MARK: - Admin Overrides

    private var adminWaitOverrides: [UUID: AdminWaitTimeOverride] = [:]
    private var adminFacilityOverrides: [UUID: AdminFacilityIssueOverride] = [:]

    private var adminWaitListener: ListenerRegistration?
    private var adminFacilityListener: ListenerRegistration?

    private var hasStartedAdminListeners = false

    // MARK: - Initialization
    private init() {
        // Attempt to load from Firestore first; fall back to local cache
        Task { [weak self] in
            await self?.loadFromFirestore()
            self?.startCareCentersListener()
            self?.startAdminOverrideListenersIfNeeded()
            // Opportunistic purge on startup, throttled
            await self?.purgeStaleUnverifiedFacilityIssuesIfNeeded()
        }
    }
    
    // MARK: - Firestore Integration

    /// Begin listening to real-time changes for care centers
    func startCareCentersListener() {
        careCentersListener?.remove()
        careCentersListener = db.collection("careCenters").addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error {
                print("Firestore listener error: \(error)")
                return
            }
            guard let snapshot = snapshot else { return }
            do {
                let centers: [CareCenter] = try snapshot.documents.compactMap { doc in
                    var data = doc.data()
                    if data["id"] == nil { data["id"] = doc.documentID }
                    let json = try JSONSerialization.data(withJSONObject: data, options: [])
                    return try JSONDecoder().decode(CareCenter.self, from: json)
                }

                // Ingest embedded manual wait time fields from care center docs (waitTimeMinutes / waitTime)
                self.ingestEmbeddedAdminWaitOverrides(from: snapshot)

                DispatchQueue.main.async {
                    self.careCenters = centers
                    self.saveCareCenters()
                    NotificationCenter.default.post(name: Notification.Name.careCentersDidChange, object: nil, userInfo: nil)
                }
            } catch {
                print("Error decoding care centers from listener: \(error)")
            }
        }
    }

    private func startAdminOverrideListenersIfNeeded() {
        guard !hasStartedAdminListeners else { return }
        hasStartedAdminListeners = true

        // Wait time overrides (whole collection listener; small scale)
        adminWaitListener?.remove()
        adminWaitListener = db.collection("adminWaitTimeOverrides").addSnapshotListener { [weak self] snap, err in
            guard let self else { return }
            if let err { print("Admin wait override listener error: \(err)"); return }
            guard let snap else { return }
            var changedIDs: Set<UUID> = []
            for diff in snap.documentChanges {
                let doc = diff.document
                let data = doc.data()
                switch diff.type {
                case .added, .modified:
                    if let model = AdminWaitTimeOverride.fromFirestore(data, docID: doc.documentID) {
                        self.adminWaitOverrides[model.careCenterID] = model
                        changedIDs.insert(model.careCenterID)
                        // Invalidate derived effective cache
                        self.waitStatsCache[model.careCenterID] = CareCenterWaitStats(careCenterID: model.careCenterID, averageMinutes: model.minutes, reportsCount: 0, lastUpdated: model.updatedAt)
                    }
                case .removed:
                    // Use docID as fallback
                    if let id = UUID(uuidString: doc.documentID) {
                        self.adminWaitOverrides[id] = nil
                        changedIDs.insert(id)
                        // Invalidate effective cache; crowd stats will be used next fetch
                        self.waitStatsCache[id] = nil
                        self.lastStatsFetchAt[id] = nil
                    }
                }
            }
            DispatchQueue.main.async {
                for centerID in changedIDs {
                    NotificationCenter.default.post(name: .adminWaitOverrideDidChange, object: centerID, userInfo: ["override": self.adminWaitOverrides[centerID] as Any])
                    // Also emit waitStatsDidChange for consumers that only listen to stats
                    if let eff = self.cachedEffectiveWaitStats(for: centerID) {
                        NotificationCenter.default.post(name: .waitStatsDidChange, object: centerID, userInfo: ["stats": eff])
                    } else if let cached = self.waitStatsCache[centerID] {
                        NotificationCenter.default.post(name: .waitStatsDidChange, object: centerID, userInfo: ["stats": cached])
                    }
                }
            }
        }

        // Facility issue overrides
        adminFacilityListener?.remove()
        adminFacilityListener = db.collection("adminFacilityIssueOverrides").addSnapshotListener { [weak self] snap, err in
            guard let self else { return }
            if let err { print("Admin facility override listener error: \(err)"); return }
            guard let snap else { return }
            var changedIDs: Set<UUID> = []
            for diff in snap.documentChanges {
                let doc = diff.document
                let data = doc.data()
                switch diff.type {
                case .added, .modified:
                    if let model = AdminFacilityIssueOverride.fromFirestore(data, docID: doc.documentID) {
                        self.adminFacilityOverrides[model.careCenterID] = model
                        changedIDs.insert(model.careCenterID)
                    }
                case .removed:
                    if let id = UUID(uuidString: doc.documentID) {
                        self.adminFacilityOverrides[id] = nil
                        changedIDs.insert(id)
                    }
                }
            }
            DispatchQueue.main.async {
                for centerID in changedIDs {
                    NotificationCenter.default.post(name: .adminFacilityOverrideDidChange, object: centerID, userInfo: ["override": self.adminFacilityOverrides[centerID] as Any])
                    // Also emit facilityIssuesDidChange so UIs that only observe issues update
                    let effective = self.cachedEffectiveFacilityIssues(for: centerID) ?? []
                    NotificationCenter.default.post(name: .facilityIssuesDidChange, object: centerID, userInfo: ["issues": effective])
                }
            }
        }
    }

    deinit {
        careCentersListener?.remove()
        adminWaitListener?.remove()
        adminFacilityListener?.remove()
    }

    /// Load care centers from Firestore and update local cache
    @MainActor
    func loadFromFirestore() async {
        do {
            let snapshot = try await db.collection("careCenters").getDocuments()
            let centers: [CareCenter] = try snapshot.documents.compactMap { doc in
                var data = doc.data()
                // Ensure the document has an `id`; if not, use the documentID
                if data["id"] == nil { data["id"] = doc.documentID }
                let json = try JSONSerialization.data(withJSONObject: data, options: [])
                return try JSONDecoder().decode(CareCenter.self, from: json)
            }

            // Ingest embedded manual wait fields from care center docs
            ingestEmbeddedAdminWaitOverrides(from: snapshot)

            self.careCenters = centers
            saveCareCenters() // update local cache
            NotificationCenter.default.post(name: Notification.Name.careCentersDidChange, object: nil, userInfo: nil)
            // If empty, seed initial data in Firestore
            if centers.isEmpty {
                try await seedFirestoreIfEmpty()
                NotificationCenter.default.post(name: Notification.Name.careCentersDidChange, object: nil, userInfo: nil)
            }
        } catch {
            // Fall back to local cache
            print("Error loading from Firestore: \(error.localizedDescription). Falling back to local cache.")
            loadCareCenters()
            NotificationCenter.default.post(name: Notification.Name.careCentersDidChange, object: nil, userInfo: nil)
        }
    }
    
    /// Seed initial data into Firestore if the collection is empty
    @MainActor
    func seedFirestoreIfEmpty() async throws {
        let collection = db.collection("careCenters")
        let existing = try await collection.limit(to: 1).getDocuments()
        if !existing.documents.isEmpty { return }

        // Use the same seed data we generate locally, but write to Firestore
        let seeded = generateSeedCareCenters()
        self.careCenters = seeded
        saveCareCenters()

        for center in seeded {
            do {
                let encoded = try JSONEncoder().encode(center)
                let jsonObject = try JSONSerialization.jsonObject(with: encoded, options: []) as? [String: Any] ?? [:]
                let docId = center.id.uuidString
                try await collection.document(docId).setData(jsonObject, merge: true)
            } catch {
                print("Failed to write seed center to Firestore: \(error)")
            }
        }
    }
    
    // MARK: - CRUD Operations
    
    /// Create a new care center
    func create(_ careCenter: CareCenter) {
        careCenters.append(careCenter)
        NotificationCenter.default.post(name: Notification.Name.careCentersDidChange, object: nil, userInfo: nil)
        Task {
            do {
                let data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(careCenter)) as? [String: Any] ?? [:]
                try await db.collection("careCenters").document(careCenter.id.uuidString).setData(data, merge: true)
            } catch {
                print("Error creating care center in Firestore: \(error)")
            }
        }
        saveCareCenters()
    }
    
    /// Read all care centers
    func readAll() -> [CareCenter] {
        return careCenters
    }
    
    /// Read a specific care center by ID
    func read(id: UUID) -> CareCenter? {
        return careCenters.first { $0.id == id }
    }
    
    /// Update an existing care center
    func update(_ careCenter: CareCenter) {
        guard let index = careCenters.firstIndex(where: { $0.id == careCenter.id }) else {
            return
        }
        careCenters[index] = careCenter
        NotificationCenter.default.post(name: Notification.Name.careCentersDidChange, object: nil, userInfo: nil)
        Task {
            do {
                let data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(careCenter)) as? [String: Any] ?? [:]
                try await db.collection("careCenters").document(careCenter.id.uuidString).setData(data, merge: true)
            } catch {
                print("Error updating care center in Firestore: \(error)")
            }
        }
        saveCareCenters()
    }
    
    /// Delete a care center by ID
    func delete(id: UUID) {
        careCenters.removeAll { $0.id == id }
        NotificationCenter.default.post(name: Notification.Name.careCentersDidChange, object: nil, userInfo: nil)
        Task {
            do {
                try await db.collection("careCenters").document(id.uuidString).delete()
            } catch {
                print("Error deleting care center in Firestore: \(error)")
            }
        }
        saveCareCenters()
    }
    
    /// Delete care centers at specific indices
    func delete(at indices: [Int]) {
        let sortedIndices = indices.sorted(by: >)
        for index in sortedIndices {
            guard index >= 0 && index < careCenters.count else { continue }
            careCenters.remove(at: index)
        }
        NotificationCenter.default.post(name: Notification.Name.careCentersDidChange, object: nil, userInfo: nil)
        // Since mapping indices post-removal is error-prone, prefer deleting by re-syncing differences
        Task {
            do {
                // Fetch all docs and delete those no longer present
                let ids = Set(careCenters.map { $0.id.uuidString })
                let snapshot = try await db.collection("careCenters").getDocuments()
                for doc in snapshot.documents where !ids.contains(doc.documentID) {
                    try await doc.reference.delete()
                }
            } catch {
                print("Error syncing deletions in Firestore: \(error)")
            }
        }
        saveCareCenters()
    }
    
    /// Delete all care centers
    func deleteAll() {
        careCenters.removeAll()
        NotificationCenter.default.post(name: Notification.Name.careCentersDidChange, object: nil, userInfo: nil)
        Task {
            do {
                let collection = db.collection("careCenters")
                let snapshot = try await collection.getDocuments()
                for doc in snapshot.documents { try await doc.reference.delete() }
            } catch {
                print("Error deleting all care centers in Firestore: \(error)")
            }
        }
        saveCareCenters()
    }
    
    // MARK: - Search & Filter
    
    /// Search care centers by name
    func search(name: String) -> [CareCenter] {
        guard !name.isEmpty else { return careCenters }
        return careCenters.filter { $0.name.localizedCaseInsensitiveContains(name) }
    }
    
    /// Filter care centers by capability (match by capability name, case/whitespace-insensitive)
    func filter(byCapability capability: Capability) -> [CareCenter] {
        let target = capability.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return careCenters.filter { center in
            center.capabilities.contains {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target
            }
        }
        }
    
    /// Filter care centers within a distance (in meters) from a location
    func filter(nearLatitude latitude: Double, longitude: Double, within distance: Double) -> [CareCenter] {
        return careCenters.filter { careCenter in
            let dist = calculateDistance(
                lat1: latitude,
                lon1: longitude,
                lat2: careCenter.latitude,
                lon2: careCenter.longitude
            )
            return dist <= distance
        }
    }
    
    /// Get unique capabilities across all care centers, deduped by name (case/whitespace-insensitive) and sorted by name.
    func getAllCapabilities() -> [Capability] {
        var byName: [String: Capability] = [:] // key: normalized name
        for center in careCenters {
            for cap in center.capabilities {
                let key = cap.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if byName[key] == nil {
                    byName[key] = cap
                }
            }
        }
        return byName.values.sorted { $0.name < $1.name }
    }
    
    // MARK: - Wait Time Reports & Stats

    private var waitReportsCollection: CollectionReference {
        db.collection("waitTimeReports")
    }

    /// Returns a stable anonymous userID. Prefer Firebase Auth UID; fallback to Firebase Installations; then local UUID.
    func anonymousUserID() async -> String {
        // Prefer Auth uid
        if let uid = Auth.auth().currentUser?.uid {
            return uid
        }
        // Try to sign in anonymously if not already
        if Auth.auth().currentUser == nil {
            if let result = try? await Auth.auth().signInAnonymously() {
                return result.user.uid
            }
        }
        // Try Firebase Installations as a stable ID fallback
        if let id = try? await Installations.installations().installationID() {
            UserDefaults.standard.set(id, forKey: "anonymousUserID")
            return id
        }
        // Last resort: local UUID
        if let cached = UserDefaults.standard.string(forKey: "anonymousUserID") {
            return cached
        }
        let local = UUID().uuidString
        UserDefaults.standard.set(local, forKey: "anonymousUserID")
        return local
    }

    /// Require a real Firebase Auth user (anonymous is OK). Throws if sign-in fails.
    private func requireAuthUID() async throws -> String {
        if let uid = Auth.auth().currentUser?.uid {
            return uid
        }
        do {
            let result = try await Auth.auth().signInAnonymously()
            return result.user.uid
        } catch {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Could not authenticate. Please try again."])
        }
    }

    /// Client-side rate limit: 1 report per user per care center per hour.
    private func canSubmitReport(userID: String, careCenterID: UUID) -> Bool {
        let key = "\(rateLimitKey).\(userID).\(careCenterID.uuidString)"
        if let last = UserDefaults.standard.object(forKey: key) as? Date {
            if Date().timeIntervalSince(last) < 3600 {
                return false
            }
        }
        return true
    }

    private func recordReportSubmission(userID: String, careCenterID: UUID) {
        let key = "\(rateLimitKey).\(userID).\(careCenterID.uuidString)"
        UserDefaults.standard.set(Date(), forKey: key)
    }

    /// Submit a wait time report if allowed by rate limit.
    func submitWaitTime(careCenterID: UUID, minutes: Int) async throws {
        // Ensure we are authenticated (anonymous is fine)
        let userID = try await requireAuthUID()
        guard canSubmitReport(userID: userID, careCenterID: careCenterID) else {
            throw NSError(domain: "WaitTime", code: 429, userInfo: [NSLocalizedDescriptionKey: "You can submit one report per hour for this location."])
        }

        let report = WaitTimeReport(careCenterID: careCenterID, userID: userID, minutes: minutes, createdAt: Date())
        var data = report.firestoreData
        // Enforce server timestamp so rules can validate createdAt == request.time
        data["createdAt"] = FieldValue.serverTimestamp()

        try await waitReportsCollection.document(report.id.uuidString).setData(data, merge: false)

        // Record locally for rate limiting
        recordReportSubmission(userID: userID, careCenterID: careCenterID)

        // Invalidate cache and refetch stats for this care center
        waitStatsCache[careCenterID] = nil
        lastStatsFetchAt[careCenterID] = nil
        // Fire a stats refresh
        _ = try? await fetchWaitStats(careCenterID: careCenterID, force: true)
    }

    /// Fetch average wait stats over the last 4 hours (crowd only; ignores admin override).
    /// Caches results briefly to avoid excessive reads.
    func fetchWaitStats(careCenterID: UUID, force: Bool = false) async throws -> CareCenterWaitStats {
        // If an admin override exists, synthesize stats and return immediately.
        if let override = adminWaitOverrides[careCenterID] {
            let stats = CareCenterWaitStats(careCenterID: careCenterID, averageMinutes: override.minutes, reportsCount: 0, lastUpdated: override.updatedAt)
            waitStatsCache[careCenterID] = stats
            lastStatsFetchAt[careCenterID] = Date()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .waitStatsDidChange, object: careCenterID, userInfo: ["stats": stats])
            }
            return stats
        }

        if !force,
           let last = lastStatsFetchAt[careCenterID],
           Date().timeIntervalSince(last) < minStatsRefetchInterval,
           let cached = waitStatsCache[careCenterID] {
            return cached
        }

        let earliest = Calendar.current.date(byAdding: .hour, value: -statsLookbackHours, to: Date()) ?? Date().addingTimeInterval(-4 * 3600)

        let query = waitReportsCollection
            .whereField("careCenterID", isEqualTo: careCenterID.uuidString)
            .whereField("createdAt", isGreaterThan: earliest)
            .order(by: "createdAt", descending: true)

        let snapshot = try await query.getDocuments()
        let reports: [WaitTimeReport] = snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let idStr = data["id"] as? String,
                  let id = UUID(uuidString: idStr),
                  let careIDStr = data["careCenterID"] as? String,
                  let careID = UUID(uuidString: careIDStr),
                  let userID = data["userID"] as? String,
                  let minutes = data["minutes"] as? Int,
                  let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? data["createdAt"] as? Date
            else { return nil }
            return WaitTimeReport(id: id, careCenterID: careID, userID: userID, minutes: minutes, createdAt: createdAt)
        }

        let count = reports.count
        let avg = count > 0 ? Int((reports.map { Double($0.minutes) }.reduce(0, +) / Double(count)).rounded()) : 0
        let stats = CareCenterWaitStats(careCenterID: careCenterID, averageMinutes: avg, reportsCount: count, lastUpdated: Date())

        waitStatsCache[careCenterID] = stats
        lastStatsFetchAt[careCenterID] = Date()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .waitStatsDidChange, object: careCenterID, userInfo: ["stats": stats])
        }

        return stats
    }

    /// Effective stats: prefer admin override if present, otherwise crowd stats (cached or fetched).
    func effectiveWaitStats(careCenterID: UUID, force: Bool = false) async -> CareCenterWaitStats {
        if let override = adminWaitOverrides[careCenterID] {
            let stats = CareCenterWaitStats(careCenterID: careCenterID, averageMinutes: override.minutes, reportsCount: 0, lastUpdated: override.updatedAt)
            waitStatsCache[careCenterID] = stats
            lastStatsFetchAt[careCenterID] = Date()
            return stats
        }
        // Fall back to cached or fetch
        if let cached = waitStatsCache[careCenterID], !force {
            return cached
        }
        if let fetched = try? await fetchWaitStats(careCenterID: careCenterID, force: force) {
            return fetched
        }
        return CareCenterWaitStats(careCenterID: careCenterID, averageMinutes: 0, reportsCount: 0, lastUpdated: Date.distantPast)
    }

    /// Convenience accessor for cached effective stats (admin override if present; else cached crowd)
    func cachedEffectiveWaitStats(for careCenterID: UUID) -> CareCenterWaitStats? {
        if let override = adminWaitOverrides[careCenterID] {
            return CareCenterWaitStats(careCenterID: careCenterID, averageMinutes: override.minutes, reportsCount: 0, lastUpdated: override.updatedAt)
        }
        return waitStatsCache[careCenterID]
    }

    // MARK: - Facility Issues

    private var facilityIssuesCollection: CollectionReference { db.collection("facilityIssues") }
    private var facilityIssueReportsCollection: CollectionReference { db.collection("facilityIssueReports") }

    private func canSubmitFacilityIssue(userID: String, careCenterID: UUID) -> Bool {
        let key = "\(facilityRateLimitKey).\(userID).\(careCenterID.uuidString)"
        if let last = UserDefaults.standard.object(forKey: key) as? Date {
            if Date().timeIntervalSince(last) < 3600 {
                return false
            }
        }
        return true
    }

    private func recordFacilityIssueSubmission(userID: String, careCenterID: UUID) {
        let key = "\(facilityRateLimitKey).\(userID).\(careCenterID.uuidString)"
        UserDefaults.standard.set(Date(), forKey: key)
    }

    func submitFacilityIssue(careCenterID: UUID, category: FacilityIssueCategory, details: String?) async throws {
        // Ensure we are authenticated (anonymous is fine)
        let userID = try await requireAuthUID()
        guard canSubmitFacilityIssue(userID: userID, careCenterID: careCenterID) else {
            throw NSError(domain: "FacilityIssue", code: 429, userInfo: [NSLocalizedDescriptionKey: "You can submit one facility issue report per hour for this location."])
        }

        let detailsKey = (details ?? "").normalizedKey()
        // aggregation key: careCenterID + category + detailsKey
        // Query for existing aggregated issue
        let query = facilityIssuesCollection
            .whereField("careCenterID", isEqualTo: careCenterID.uuidString)
            .whereField("category", isEqualTo: category.rawValue)
            .whereField("detailsKey", isEqualTo: detailsKey)

        let snapshot = try await query.limit(to: 1).getDocuments()

        var issue: FacilityIssue
        if let doc = snapshot.documents.first, let parsed = FacilityIssue.fromFirestore(doc.data()) {
            issue = parsed

            // Build an atomic update: +1 reportsCount, server timestamp, and set details if missing and provided.
            var update: [String: Any] = [
                "reportsCount": FieldValue.increment(Int64(1)),
                "lastUpdated": FieldValue.serverTimestamp()
            ]
            if (issue.details == nil || issue.details?.isEmpty == true), let d = details, !d.isEmpty {
                update["details"] = d
            }
            try await facilityIssuesCollection.document(issue.id.uuidString).setData(update, merge: true)

            // Mirror the updated fields locally
            issue.reportsCount += 1
            issue.lastUpdated = Date()
            if (issue.details == nil || issue.details?.isEmpty == true), let d = details, !d.isEmpty {
                issue.details = d
            }
        } else {
            // create new aggregated issue (lastUpdated via serverTimestamp)
            issue = FacilityIssue(careCenterID: careCenterID, category: category, detailsKey: detailsKey, details: details, reportsCount: 1, isVerified: false, lastUpdated: Date())
            var data = issue.firestoreData
            data["lastUpdated"] = FieldValue.serverTimestamp()
            try await facilityIssuesCollection.document(issue.id.uuidString).setData(data, merge: false)
        }

        // Write raw report (createdAt via serverTimestamp)
        let raw = FacilityIssueReport(issueID: issue.id, careCenterID: careCenterID, userID: userID, category: category, detailsKey: detailsKey, details: details, createdAt: Date())
        var rawData = raw.firestoreData
        rawData["createdAt"] = FieldValue.serverTimestamp()
        try await facilityIssueReportsCollection.document(raw.id.uuidString).setData(rawData, merge: false)

        // Update cache
        var arr = issuesCache[careCenterID] ?? []
        if let idx = arr.firstIndex(where: { $0.id == issue.id }) {
            arr[idx] = issue
        } else {
            arr.append(issue)
        }
        issuesCache[careCenterID] = arr
        lastIssuesFetchAt[careCenterID] = Date()

        recordFacilityIssueSubmission(userID: userID, careCenterID: careCenterID)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .facilityIssuesDidChange, object: careCenterID, userInfo: ["issues": arr])
        }
    }

    func fetchFacilityIssues(careCenterID: UUID, force: Bool = false) async throws -> [FacilityIssue] {
        if !force,
           let last = lastIssuesFetchAt[careCenterID],
           Date().timeIntervalSince(last) < minIssuesRefetchInterval,
           let cached = issuesCache[careCenterID] {
            return cached
        }
        let snapshot = try await facilityIssuesCollection
            .whereField("careCenterID", isEqualTo: careCenterID.uuidString)
            .getDocuments()

        let issues: [FacilityIssue] = snapshot.documents.compactMap { FacilityIssue.fromFirestore($0.data()) }
            .sorted { lhs, rhs in
                // Verified first, then by lastUpdated desc
                if lhs.isVerified != rhs.isVerified { return lhs.isVerified && !rhs.isVerified }
                return lhs.lastUpdated > rhs.lastUpdated
            }

        issuesCache[careCenterID] = issues
        lastIssuesFetchAt[careCenterID] = Date()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .facilityIssuesDidChange, object: careCenterID, userInfo: ["issues": issues])
        }
        return issues
    }

    func cachedFacilityIssues(for careCenterID: UUID) -> [FacilityIssue]? {
        return issuesCache[careCenterID]
    }

    // Admin verification toggle (call from a privileged UI or tool)
    func setFacilityIssueVerified(issueID: UUID, isVerified: Bool) async throws {
        let ref = facilityIssuesCollection.document(issueID.uuidString)
        try await ref.setData(["isVerified": isVerified, "lastUpdated": Date()], merge: true)

        // Update caches and notify for any care center that had this issue
        let doc = try await ref.getDocument()
        if let data = doc.data(), let updated = FacilityIssue.fromFirestore(data) {
            var arr = issuesCache[updated.careCenterID] ?? []
            if let idx = arr.firstIndex(where: { $0.id == updated.id }) {
                arr[idx] = updated
            }
            issuesCache[updated.careCenterID] = arr
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .facilityIssuesDidChange, object: updated.careCenterID, userInfo: ["issues": arr])
            }
        }
    }

    // MARK: - Effective Facility Issues (admin + crowd)

    /// Returns the effective set of facility issues for display.
    /// If an admin override exists, an "Admin Notice" should be displayed on top of the normal crowd issues.
    func effectiveFacilityIssues(careCenterID: UUID, force: Bool = false) async -> [FacilityIssue] {
        // We keep the crowd issues as-is; the admin notice is handled in the UI with a separate model.
        if !force, let cached = issuesCache[careCenterID] {
            return cached
        }
        if let fetched = try? await fetchFacilityIssues(careCenterID: careCenterID, force: force) {
            return fetched
        }
        return []
    }

    /// Convenience accessor for cached effective list (crowd only; admin notice handled in UI).
    func cachedEffectiveFacilityIssues(for careCenterID: UUID) -> [FacilityIssue]? {
        return issuesCache[careCenterID]
    }

    // MARK: - Purge stale unverified facility issues

    /// Throttled wrapper to avoid excessive reads.
    func purgeStaleUnverifiedFacilityIssuesIfNeeded() async {
        let now = Date()
        if let last = UserDefaults.standard.object(forKey: lastFacilityPurgeKey) as? Date,
           now.timeIntervalSince(last) < minPurgeInterval {
            return
        }
        await purgeStaleUnverifiedFacilityIssues(olderThan: 24 * 3600)
        UserDefaults.standard.set(now, forKey: lastFacilityPurgeKey)
    }

    /// Deletes unverified FacilityIssue documents older than the given age (seconds) and their reports.
    func purgeStaleUnverifiedFacilityIssues(olderThan ageSeconds: TimeInterval) async {
        let cutoff = Date().addingTimeInterval(-ageSeconds)
        do {
            // Query unverified issues older than cutoff
            let query = facilityIssuesCollection
                .whereField("isVerified", isEqualTo: false)
                .whereField("lastUpdated", isLessThanOrEqualTo: cutoff)

            let snapshot = try await query.getDocuments()
            guard !snapshot.documents.isEmpty else { return }

            // Group affected care centers for cache/notification updates
            var affectedCenters: Set<UUID> = []

            for doc in snapshot.documents {
                let data = doc.data()
                guard let issue = FacilityIssue.fromFirestore(data) else {
                    // If parsing fails, still attempt to delete the doc to avoid leaks
                    try await doc.reference.delete()
                    continue
                }
                affectedCenters.insert(issue.careCenterID)

                // Delete all raw reports for this issue
                let reportsSnap = try await facilityIssueReportsCollection
                    .whereField("issueID", isEqualTo: issue.id.uuidString)
                    .getDocuments()
                for r in reportsSnap.documents {
                    try await r.reference.delete()
                }

                // Delete the aggregate issue
                try await facilityIssuesCollection.document(issue.id.uuidString).delete()

                // Remove from in-memory cache
                if var list = issuesCache[issue.careCenterID] {
                    list.removeAll { $0.id == issue.id }
                    issuesCache[issue.careCenterID] = list
                }
            }

            // Notify UI for each affected care center
            DispatchQueue.main.async {
                for centerID in affectedCenters {
                    let current = self.issuesCache[centerID] ?? []
                    NotificationCenter.default.post(name: .facilityIssuesDidChange, object: centerID, userInfo: ["issues": current])
                }
            }
        } catch {
            print("Error purging stale unverified facility issues: \(error)")
        }
    }

    // MARK: - Persistence
    
    private var careCentersURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("careCenters.json")
    }
    
    private func saveCareCenters() {
        do {
            let data = try JSONEncoder().encode(careCenters)
            try data.write(to: careCentersURL)
        } catch {
            print("Error saving care centers: \(error.localizedDescription)")
        }
    }
    
    private func loadCareCenters() {
        do {
            let data = try Data(contentsOf: careCentersURL)
            careCenters = try JSONDecoder().decode([CareCenter].self, from: data)
            
            // Check if the loaded data has the new fields, if not, reseed
            let hasNewFields = careCenters.contains { careCenter in
                careCenter.type != nil || careCenter.dailyHours != nil || 
                careCenter.phoneNumber != nil || careCenter.email != nil
            }
            
            if !hasNewFields {
                print("Loaded care centers don't have new fields. Reseeding with updated data.")
                seedSampleData()
            }
            NotificationCenter.default.post(name: Notification.Name.careCentersDidChange, object: nil, userInfo: nil)
        } catch {
            // If file doesn't exist or can't be decoded, seed with sample data
            print("No existing care centers found or error loading: \(error.localizedDescription)")
            seedSampleData()
            NotificationCenter.default.post(name: Notification.Name.careCentersDidChange, object: nil, userInfo: nil)
        }
    }
    
    /// Generate the sample care centers without persisting
    private func generateSeedCareCenters() -> [CareCenter] {
        // Define common capabilities
        let emergencyCare = Capability(name: "Emergency Care")
        let surgery = Capability(name: "Surgery")
        let pediatrics = Capability(name: "Pediatrics")
        let cardiology = Capability(name: "Cardiology")
        let radiology = Capability(name: "Radiology")
        let oncology = Capability(name: "Oncology")
        let maternity = Capability(name: "Maternity")
        let orthopedics = Capability(name: "Orthopedics")
        let urgentCare = Capability(name: "Urgent Care")
        let pharmacy = Capability(name: "Pharmacy")

        // Create sample care centers near Victoria Harbour, Ontario, Canada
        return [
            CareCenter(
                name: "Georgian Bay General Hospital",
                streetAddress: "1112 St. Andrews Drive",
                city: "Midland",
                region: "Ontario",
                country: "Canada",
                capabilities: [emergencyCare, surgery, cardiology, radiology, oncology, maternity],
                latitude: 44.74202,
                longitude: -79.913687,
                type: "Hospital",
                dailyHours: "Open 24 Hours",
                phoneNumber: "(705) 526-1300",
                email: "info@gbgh.on.ca"
            ),
            CareCenter(
                name: "Victoria Harbour Medical Centre",
                streetAddress: "2545 Elm Street",
                city: "Victoria Harbour",
                region: "Ontario",
                country: "Canada",
                capabilities: [urgentCare, pharmacy, radiology],
                latitude: 44.7231,
                longitude: -79.7864,
                type: "Medical Clinic",
                dailyHours: "Mon-Fri 8:00 AM - 6:00 PM, Sat 9:00 AM - 2:00 PM",
                phoneNumber: "(705) 534-7305",
                email: "appointments@vhmedical.ca"
            ),
            CareCenter(
                name: "Penetanguishene General Hospital",
                streetAddress: "9 Robert Street West",
                city: "Penetanguishene",
                region: "Ontario",
                country: "Canada",
                capabilities: [emergencyCare, pediatrics, orthopedics, radiology, pharmacy],
                latitude: 44.7667,
                longitude: -79.9333,
                type: "Hospital",
                dailyHours: "Open 24 Hours",
                phoneNumber: "(705) 549-3453",
                email: "contact@pengenhosp.on.ca"
            ),
            CareCenter(
                name: "Tay Township Family Clinic",
                streetAddress: "456 County Road 27",
                city: "Tay",
                region: "Ontario",
                country: "Canada",
                capabilities: [urgentCare, pediatrics, pharmacy],
                latitude: 44.7100,
                longitude: -79.7500,
                type: "Family Clinic",
                dailyHours: "Mon-Fri 9:00 AM - 5:00 PM",
                phoneNumber: "(705) 534-8922",
                email: "reception@tayfamilyclinic.ca"
            ),
            CareCenter(
                name: "Orillia Soldiers' Memorial Hospital",
                streetAddress: "170 Colborne Street West",
                city: "Orillia",
                region: "Ontario",
                country: "Canada",
                capabilities: [emergencyCare, surgery, orthopedics, radiology, cardiology, maternity],
                latitude: 44.6081,
                longitude: -79.4194,
                type: "Hospital",
                dailyHours: "Open 24 Hours",
                phoneNumber: "(705) 325-2201",
                email: "info@osmh.on.ca"
            ),
            CareCenter(
                name: "Port McNicoll Urgent Care",
                streetAddress: "789 Bay Street",
                city: "Port McNicoll",
                region: "Ontario",
                country: "Canada",
                capabilities: [urgentCare, radiology, pharmacy],
                latitude: 44.7667,
                longitude: -79.8000,
                type: "Urgent Care Centre",
                dailyHours: "7 Days 8:00 AM - 10:00 PM",
                phoneNumber: "(705) 534-7788",
                email: "urgent@portmcnicollcare.ca"
            )
        ]
    }
    
    /// Seed sample care centers data
    private func seedSampleData() {
        let seeded = generateSeedCareCenters()
        self.careCenters = seeded
        saveCareCenters()

        Task {
            do {
                let collection = db.collection("careCenters")
                for center in seeded {
                    let encoded = try JSONEncoder().encode(center)
                    let jsonObject = try JSONSerialization.jsonObject(with: encoded, options: []) as? [String: Any] ?? [:]
                    try await collection.document(center.id.uuidString).setData(jsonObject, merge: true)
                }
                print("Seeded \(seeded.count) sample care centers to Firestore and local cache")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name.careCentersDidChange, object: nil, userInfo: nil)
                }
            } catch {
                print("Error seeding to Firestore: \(error)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Calculate distance between two coordinates using Haversine formula (returns meters)
    private func calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadius = 6371000.0 // meters
        
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        return earthRadius * c
    }

    // MARK: - Embedded Admin Wait Override ingestion

    /// Reads optional waitTimeMinutes / waitTime fields embedded on care center documents
    /// and updates the effective wait stats + notifications.
    private func ingestEmbeddedAdminWaitOverrides(from snapshot: QuerySnapshot) {
        var changedIDs: Set<UUID> = []

        for doc in snapshot.documents {
            let data = doc.data()
            // Resolve the care center ID from docID or explicit field
            let idStr = (data["id"] as? String) ?? doc.documentID
            guard let centerID = UUID(uuidString: idStr) else { continue }

            // Prefer explicit integer minutes
            var minutes: Int? = data["waitTimeMinutes"] as? Int

            // Fallback: parse "waitTime" if present (accept Int, Double, or String with digits)
            if minutes == nil {
                if let v = data["waitTime"] {
                    if let i = v as? Int { minutes = i }
                    else if let d = v as? Double { minutes = Int(d.rounded()) }
                    else if let s = v as? String {
                        let digits = s.filter { $0.isNumber }
                        if let parsed = Int(digits) { minutes = parsed }
                    }
                }
            }

            // Optional metadata: if your web app later adds waitTimeUpdatedAt, we’ll use it
            let updatedAt: Date = {
                if let d = data["waitTimeUpdatedAt"] as? Date { return d }
                if let ts = data["waitTimeUpdatedAt"] as? Timestamp { return ts.dateValue() }
                return Date()
            }()

            if let m = minutes, m > 0 {
                let newOverride = AdminWaitTimeOverride(careCenterID: centerID, minutes: m, reason: nil, updatedAt: updatedAt, updatedBy: nil)
                if adminWaitOverrides[centerID] != newOverride {
                    adminWaitOverrides[centerID] = newOverride
                    // Synthesize effective stats and cache them
                    waitStatsCache[centerID] = CareCenterWaitStats(careCenterID: centerID, averageMinutes: m, reportsCount: 0, lastUpdated: updatedAt)
                    lastStatsFetchAt[centerID] = Date()
                    changedIDs.insert(centerID)
                }
            } else {
                // No override or <= 0 -> clear any existing override
                if adminWaitOverrides[centerID] != nil {
                    adminWaitOverrides[centerID] = nil
                    waitStatsCache[centerID] = nil
                    lastStatsFetchAt[centerID] = nil
                    changedIDs.insert(centerID)
                }
            }
        }

        if !changedIDs.isEmpty {
            DispatchQueue.main.async {
                for centerID in changedIDs {
                    NotificationCenter.default.post(name: .adminWaitOverrideDidChange, object: centerID, userInfo: ["override": self.adminWaitOverrides[centerID] as Any])
                    if let eff = self.cachedEffectiveWaitStats(for: centerID) {
                        NotificationCenter.default.post(name: .waitStatsDidChange, object: centerID, userInfo: ["stats": eff])
                    }
                }
            }
        }
    }
}

