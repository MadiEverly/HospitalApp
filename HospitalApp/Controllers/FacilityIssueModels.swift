import Foundation
import UIKit
import FirebaseFirestore

enum FacilityIssueCategory: String, Codable, CaseIterable, Hashable {
    case xray = "X-ray"
    case ct = "CT"
    case mri = "MRI"
    case lab = "Lab"
    case pharmacy = "Pharmacy"
    case other = "Other"

    var displayName: String { rawValue }
    var icon: String {
        switch self {
        case .xray: return "🩻"
        case .ct: return "🖥️"
        case .mri: return "🧲"
        case .lab: return "🧪"
        case .pharmacy: return "💊"
        case .other: return "⚠️"
        }
    }
}

struct FacilityIssue: Codable, Identifiable, Hashable {
    let id: UUID
    let careCenterID: UUID
    let category: FacilityIssueCategory
    let detailsKey: String // normalized details key (lowercased trimmed), empty if none
    var details: String? // human text shown if present
    var reportsCount: Int
    var isVerified: Bool
    var lastUpdated: Date

    init(id: UUID = UUID(), careCenterID: UUID, category: FacilityIssueCategory, detailsKey: String, details: String?, reportsCount: Int, isVerified: Bool, lastUpdated: Date = Date()) {
        self.id = id
        self.careCenterID = careCenterID
        self.category = category
        self.detailsKey = detailsKey
        self.details = details
        self.reportsCount = reportsCount
        self.isVerified = isVerified
        self.lastUpdated = lastUpdated
    }

    var firestoreData: [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "careCenterID": careCenterID.uuidString,
            "category": category.rawValue,
            "detailsKey": detailsKey,
            "reportsCount": reportsCount,
            "isVerified": isVerified,
            "lastUpdated": lastUpdated
        ]
        if let details = details, !details.isEmpty {
            dict["details"] = details
        }
        return dict
    }

    static func fromFirestore(_ data: [String: Any]) -> FacilityIssue? {
        guard
            let idStr = data["id"] as? String, let id = UUID(uuidString: idStr),
            let careCenterStr = data["careCenterID"] as? String, let careCenterID = UUID(uuidString: careCenterStr),
            let categoryStr = data["category"] as? String, let category = FacilityIssueCategory(rawValue: categoryStr),
            let detailsKey = data["detailsKey"] as? String,
            let reportsCount = data["reportsCount"] as? Int,
            let isVerified = data["isVerified"] as? Bool
        else { return nil }
        let details = data["details"] as? String
        let lastUpdated: Date
        if let ts = data["lastUpdated"] as? Date {
            lastUpdated = ts
        } else if let ts = (data["lastUpdated"] as? Timestamp)?.dateValue() {
            lastUpdated = ts
        } else {
            lastUpdated = Date()
        }
        return FacilityIssue(id: id, careCenterID: careCenterID, category: category, detailsKey: detailsKey, details: details, reportsCount: reportsCount, isVerified: isVerified, lastUpdated: lastUpdated)
    }

    var titleLine: String {
        let base = "\(category.icon) \(category.displayName) unavailable"
        if let d = details, !d.isEmpty {
            return base + " – \(d)"
        }
        return base
    }

    var statusLine: String {
        if isVerified {
            return "Verified by administration"
        } else {
            return "Unverified – \(reportsCount) report\(reportsCount == 1 ? "" : "s")"
        }
    }
}

struct FacilityIssueReport: Codable, Identifiable, Hashable {
    let id: UUID
    let issueID: UUID
    let careCenterID: UUID
    let userID: String
    let category: FacilityIssueCategory
    let detailsKey: String
    let details: String?
    let createdAt: Date

    init(id: UUID = UUID(), issueID: UUID, careCenterID: UUID, userID: String, category: FacilityIssueCategory, detailsKey: String, details: String?, createdAt: Date = Date()) {
        self.id = id
        self.issueID = issueID
        self.careCenterID = careCenterID
        self.userID = userID
        self.category = category
        self.detailsKey = detailsKey
        self.details = details
        self.createdAt = createdAt
    }

    var firestoreData: [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "issueID": issueID.uuidString,
            "careCenterID": careCenterID.uuidString,
            "userID": userID,
            "category": category.rawValue,
            "detailsKey": detailsKey,
            "createdAt": createdAt
        ]
        if let details = details, !details.isEmpty {
            dict["details"] = details
        }
        return dict
    }
}

extension Notification.Name {
    static let facilityIssuesDidChange = Notification.Name("facilityIssuesDidChange")
}

extension String {
    func normalizedKey() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
