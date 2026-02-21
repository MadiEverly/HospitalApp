//
//  CareCenterTableViewCell.swift
//  HospitalApp
//
//  Created by Duane Homick on 2026-01-30.
//

import UIKit

class CareCenterTableViewCell: UITableViewCell {
    
    // MARK: - UI Components
    private let nameLabel = UILabel()
    private let addressIconView = UIImageView()
    private let addressLabel = UILabel()
    private let capabilitiesLabel = UILabel()
    private let distanceLabel = UILabel()
    
    // MARK: - Properties
    static let reuseIdentifier = "CareCenterTableViewCell"
    
    // MARK: - Initialization
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        // Configure name label
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 0
        contentView.addSubview(nameLabel)
        
        // Configure address icon
        addressIconView.translatesAutoresizingMaskIntoConstraints = false
        addressIconView.image = UIImage(systemName: "mappin.and.ellipse")
        addressIconView.tintColor = .systemRed
        addressIconView.contentMode = .scaleAspectFit
        contentView.addSubview(addressIconView)
        
        // Configure address label
        addressLabel.translatesAutoresizingMaskIntoConstraints = false
        addressLabel.font = UIFont.systemFont(ofSize: 14)
        addressLabel.textColor = .secondaryLabel
        addressLabel.numberOfLines = 0
        contentView.addSubview(addressLabel)
        
        // Configure capabilities label
        capabilitiesLabel.translatesAutoresizingMaskIntoConstraints = false
        capabilitiesLabel.font = UIFont.systemFont(ofSize: 13)
        capabilitiesLabel.textColor = .systemBlue
        capabilitiesLabel.numberOfLines = 0
        contentView.addSubview(capabilitiesLabel)
        
        // Configure distance label
        distanceLabel.translatesAutoresizingMaskIntoConstraints = false
        distanceLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        distanceLabel.textColor = .secondaryLabel
        distanceLabel.textAlignment = .right
        contentView.addSubview(distanceLabel)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Name label - top left
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: distanceLabel.leadingAnchor, constant: -8),
            
            // Distance label - top right
            distanceLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            distanceLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            distanceLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            
            // Address icon - below name
            addressIconView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 8),
            addressIconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            addressIconView.widthAnchor.constraint(equalToConstant: 14),
            addressIconView.heightAnchor.constraint(equalToConstant: 14),
            
            // Address label - next to icon
            addressLabel.centerYAnchor.constraint(equalTo: addressIconView.centerYAnchor),
            addressLabel.leadingAnchor.constraint(equalTo: addressIconView.trailingAnchor, constant: 6),
            addressLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Capabilities label - below address
            capabilitiesLabel.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: 6),
            capabilitiesLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            capabilitiesLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            capabilitiesLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    
    // MARK: - Configuration
    func configure(with careCenter: CareCenter, distance: Double?) {
        // Set name
        nameLabel.text = careCenter.name
        
        // Set address
        addressLabel.text = careCenter.fullAddress
        
        // Set capabilities (limit to 3)
        let capabilitiesText = formatCapabilities(careCenter.capabilities)
        capabilitiesLabel.text = capabilitiesText
        
        // Set distance
        if let distance = distance {
            distanceLabel.text = formatDistance(distance)
        } else {
            distanceLabel.text = ""
        }
    }
    
    private func formatCapabilities(_ capabilities: [Capability]) -> String {
        let maxDisplay = 3
        let displayCapabilities = capabilities.prefix(maxDisplay)
        let capabilityNames = displayCapabilities.map { $0.name }
        
        var result = capabilityNames.joined(separator: " • ")
        
        if capabilities.count > maxDisplay {
            let remaining = capabilities.count - maxDisplay
            result += " +\(remaining)"
        }
        
        return result
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0f m", meters)
        } else {
            let kilometers = meters / 1000.0
            return String(format: "%.1f km", kilometers)
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        addressLabel.text = nil
        capabilitiesLabel.text = nil
        distanceLabel.text = nil
    }
}
