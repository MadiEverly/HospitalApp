//
//  DataManager.swift
//  HospitalApp
//
//  Created by Duane Homick on 2026-01-30.
//

import Foundation
import FirebaseFirestore

final class DataManager {
    
    // MARK: - Singleton
    static let shared = DataManager()
    private let db = Firestore.firestore()
    private var careCentersListener: ListenerRegistration?
    
    // MARK: - Properties
    private(set) var careCenters: [CareCenter] = []
    
    // MARK: - Initialization
    private init() {
        // Attempt to load from Firestore first; fall back to local cache
        Task { [weak self] in
            await self?.loadFromFirestore()
            self?.startCareCentersListener()
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

    deinit {
        careCentersListener?.remove()
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
    
    /// Filter care centers by capability
    func filter(byCapability capability: Capability) -> [CareCenter] {
        return careCenters.filter { $0.capabilities.contains(capability) }
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
    
    /// Get all unique capabilities from all care centers, sorted alphabetically by name
    func getAllCapabilities() -> [Capability] {
        var capabilitiesSet = Set<Capability>()
        
        for careCenter in careCenters {
            for capability in careCenter.capabilities {
                capabilitiesSet.insert(capability)
            }
        }
        
        return capabilitiesSet.sorted { $0.name < $1.name }
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
}

