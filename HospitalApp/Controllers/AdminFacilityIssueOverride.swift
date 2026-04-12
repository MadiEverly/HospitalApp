import Foundation
import FirebaseFirestore
import UIKit

enum AdminFacilitySeverity: String, Codable, CaseIterable {
    case info
    case warning
    case critical

    var color: UIColor {
        switch self {
        case .info: return .systemBlue
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }
}

struct AdminFacilityIssueOverride: Codable, Identifiable, Hashable {
    // 1:1 with careCenterID
    var id: UUID { careCenterID }
    let careCenterID: UUID
    let title: String
    let message: String
    let severity: AdminFacilitySeverity
    let updatedAt: Date
    let updatedBy: String?

    init(careCenterID: UUID, title: String, message: String, severity: AdminFacilitySeverity, updatedAt: Date = Date(), updatedBy: String? = nil) {
        self.careCenterID = careCenterID
        self.title = title
        self.message = message
        self.severity = severity
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }

    var firestoreData: [String: Any] {
        var dict: [String: Any] = [
            "careCenterID": careCenterID.uuidString,
            "title": title,
            "message": message,
            "severity": severity.rawValue,
            "updatedAt": updatedAt
        ]
        if let updatedBy, !updatedBy.isEmpty { dict["updatedBy"] = updatedBy }
        return dict
    }

    static func fromFirestore(_ data: [String: Any], docID: String) -> AdminFacilityIssueOverride? {
        let idStr = (data["careCenterID"] as? String) ?? docID
        guard let careID = UUID(uuidString: idStr),
              let title = data["title"] as? String,
              let message = data["message"] as? String,
              let severityStr = data["severity"] as? String,
              let severity = AdminFacilitySeverity(rawValue: severityStr) else {
            return nil
        }
        let updatedBy = data["updatedBy"] as? String
        let updatedAt: Date
        if let ts = data["updatedAt"] as? Date {
            updatedAt = ts
        } else if let ts = (data["updatedAt"] as? Timestamp)?.dateValue() {
            updatedAt = ts
        } else {
            updatedAt = Date()
        }
        return AdminFacilityIssueOverride(careCenterID: careID, title: title, message: message, severity: severity, updatedAt: updatedAt, updatedBy: updatedBy)
    }
}

extension Notification.Name {
    static let adminFacilityOverrideDidChange = Notification.Name("adminFacilityOverrideDidChange")
}
