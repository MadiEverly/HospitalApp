import Foundation

public struct CareCenter: Identifiable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var streetAddress: String
    public var city: String
    public var region: String
    public var country: String
    public var capabilities: [Capability]
    public var latitude: Double
    public var longitude: Double
    public var type: String?
    public var dailyHours: String?
    public var phoneNumber: String?
    public var email: String?

    public init(id: UUID = UUID(), name: String, streetAddress: String, city: String, region: String, country: String, capabilities: [Capability], latitude: Double, longitude: Double, type: String? = nil, dailyHours: String? = nil, phoneNumber: String? = nil, email: String? = nil) {
        self.id = id
        self.name = name
        self.streetAddress = streetAddress
        self.city = city
        self.region = region
        self.country = country
        self.capabilities = capabilities
        self.latitude = latitude
        self.longitude = longitude
        self.type = type
        self.dailyHours = dailyHours
        self.phoneNumber = phoneNumber
        self.email = email
    }
    
    /// Returns the full address as a formatted string
    public var fullAddress: String {
        return "\(streetAddress), \(city), \(region), \(country)"
    }
}
