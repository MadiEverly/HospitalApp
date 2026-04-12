import Foundation
import FirebaseFirestore

struct AdminWaitTimeOverride: Codable, Identifiable, Hashable {
    // We use careCenterID as the document ID for simplicity (1:1 mapping)
    var id: UUID { careCenterID }
    let careCenterID: UUID
    let minutes: Int
    let reason: String?
    let updatedAt: Date
    let updatedBy: String?

    init(careCenterID: UUID, minutes: Int, reason: String?, updatedAt: Date = Date(), updatedBy: String? = nil) {
        self.careCenterID = careCenterID
        self.minutes = minutes
        self.reason = reason
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }

    var firestoreData: [String: Any] {
        var dict: [String: Any] = [
            "careCenterID": careCenterID.uuidString,
            "minutes": minutes,
            "updatedAt": updatedAt
        ]
        if let reason, !reason.isEmpty { dict["reason"] = reason }
        if let updatedBy, !updatedBy.isEmpty { dict["updatedBy"] = updatedBy }
        return dict
    }

    static func fromFirestore(_ data: [String: Any], docID: String) -> AdminWaitTimeOverride? {
        let idStr = (data["careCenterID"] as? String) ?? docID
        guard let careID = UUID(uuidString: idStr),
              let minutes = data["minutes"] as? Int else {
            return nil
        }
        let reason = data["reason"] as? String
        let updatedBy = data["updatedBy"] as? String
        let updatedAt: Date
        if let ts = data["updatedAt"] as? Date {
            updatedAt = ts
        } else if let ts = (data["updatedAt"] as? Timestamp)?.dateValue() {
            updatedAt = ts
        } else {
            updatedAt = Date()
        }
        return AdminWaitTimeOverride(careCenterID: careID, minutes: minutes, reason: reason, updatedAt: updatedAt, updatedBy: updatedBy)
    }
}

extension Notification.Name {
    static let adminWaitOverrideDidChange = Notification.Name("adminWaitOverrideDidChange")
}
