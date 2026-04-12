import Foundation
import UIKit

struct WaitTimeReport: Codable, Identifiable, Hashable {
    let id: UUID
    let careCenterID: UUID
    let userID: String
    let minutes: Int
    let createdAt: Date

    init(id: UUID = UUID(), careCenterID: UUID, userID: String, minutes: Int, createdAt: Date = Date()) {
        self.id = id
        self.careCenterID = careCenterID
        self.userID = userID
        self.minutes = minutes
        self.createdAt = createdAt
    }

    var firestoreData: [String: Any] {
        return [
            "id": id.uuidString,
            "careCenterID": careCenterID.uuidString,
            "userID": userID,
            "minutes": minutes,
            "createdAt": createdAt
        ]
    }
}

struct CareCenterWaitStats: Codable, Hashable {
    let careCenterID: UUID
    let averageMinutes: Int
    let reportsCount: Int
    let lastUpdated: Date

    static let emptyAverage = CareCenterWaitStats(careCenterID: UUID(), averageMinutes: 0, reportsCount: 0, lastUpdated: Date.distantPast)
}

enum WaitTimeColorBucket {
    case green
    case yellow
    case red
    case unknown

    static func bucket(for minutes: Int) -> WaitTimeColorBucket {
        switch minutes {
        case Int.min...0: return .unknown
        case 1...15: return .green
        case 16...45: return .yellow
        default: return .red
        }
    }

    var color: UIColor {
        switch self {
        case .green: return UIColor.systemGreen
        case .yellow: return UIColor.systemYellow
        case .red: return UIColor.systemRed
        case .unknown: return UIColor.tertiaryLabel
        }
    }
}

extension Notification.Name {
    static let waitStatsDidChange = Notification.Name("waitStatsDidChange")
}
