//
//  CareCenterDetailHeaderCell.swift
//  HospitalApp
//
//  Created by Duane Homick on 2026-01-30.
//

import UIKit

class CareCenterDetailHeaderCell: UITableViewCell {
    
    // MARK: - UI Components
    private let nameLabel = UILabel()
    private let addressIconView = UIImageView()
    private let addressLabel = UILabel()
    private let capabilitiesLabel = UILabel()
    private let typeLabel = UILabel()
    private let hoursLabel = UILabel()
    private let phoneLabel = UILabel()
    private let emailLabel = UILabel()
    
    // MARK: - Properties
    static let reuseIdentifier = "CareCenterDetailHeaderCell"
    
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
        selectionStyle = .none
        
        // Configure name label
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = UIFont.systemFont(ofSize: 23, weight: .bold)
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
        addressLabel.font = UIFont.systemFont(ofSize: 15)
        addressLabel.textColor = .secondaryLabel
        addressLabel.numberOfLines = 0
        contentView.addSubview(addressLabel)
        
        // Configure capabilities label
        capabilitiesLabel.translatesAutoresizingMaskIntoConstraints = false
        capabilitiesLabel.font = UIFont.systemFont(ofSize: 14)
        capabilitiesLabel.textColor = .systemBlue
        capabilitiesLabel.numberOfLines = 0
        contentView.addSubview(capabilitiesLabel)
        
        // Configure type label
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        typeLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        typeLabel.textColor = .label
        typeLabel.numberOfLines = 0
        contentView.addSubview(typeLabel)
        
        // Configure hours label
        hoursLabel.translatesAutoresizingMaskIntoConstraints = false
        hoursLabel.font = UIFont.systemFont(ofSize: 15)
        hoursLabel.textColor = .secondaryLabel
        hoursLabel.numberOfLines = 0
        contentView.addSubview(hoursLabel)
        
        // Configure phone label
        phoneLabel.translatesAutoresizingMaskIntoConstraints = false
        phoneLabel.font = UIFont.systemFont(ofSize: 15)
        phoneLabel.textColor = .systemBlue
        phoneLabel.numberOfLines = 1
        contentView.addSubview(phoneLabel)
        
        // Configure email label
        emailLabel.translatesAutoresizingMaskIntoConstraints = false
        emailLabel.font = UIFont.systemFont(ofSize: 15)
        emailLabel.textColor = .systemBlue
        emailLabel.numberOfLines = 1
        contentView.addSubview(emailLabel)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Name label - top (leave space for close button: 40pt button + 12pt margin + 8pt padding = 60pt)
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -68),
            
            // Address icon - below name
            addressIconView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 16),
            addressIconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            addressIconView.widthAnchor.constraint(equalToConstant: 18),
            addressIconView.heightAnchor.constraint(equalToConstant: 18),
            
            // Address label - next to icon
            addressLabel.centerYAnchor.constraint(equalTo: addressIconView.centerYAnchor),
            addressLabel.leadingAnchor.constraint(equalTo: addressIconView.trailingAnchor, constant: 10),
            addressLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Capabilities label - below address
            capabilitiesLabel.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: 14),
            capabilitiesLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            capabilitiesLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Type label - below capabilities
            typeLabel.topAnchor.constraint(equalTo: capabilitiesLabel.bottomAnchor, constant: 14),
            typeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            typeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Hours label - below type
            hoursLabel.topAnchor.constraint(equalTo: typeLabel.bottomAnchor, constant: 10),
            hoursLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            hoursLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Phone label - below hours
            phoneLabel.topAnchor.constraint(equalTo: hoursLabel.bottomAnchor, constant: 10),
            phoneLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            phoneLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Email label - below phone
            emailLabel.topAnchor.constraint(equalTo: phoneLabel.bottomAnchor, constant: 8),
            emailLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            emailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            emailLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }
    
    // MARK: - Configuration
    func configure(with careCenter: CareCenter) {
        // Set name
        nameLabel.text = careCenter.name
        
        // Set address
        addressLabel.text = careCenter.fullAddress
        
        // Set capabilities (show all)
        let capabilitiesText = formatCapabilities(careCenter.capabilities)
        capabilitiesLabel.text = capabilitiesText
        capabilitiesLabel.isHidden = careCenter.capabilities.isEmpty
        
        // Set type
        if let type = careCenter.type, !type.isEmpty {
            typeLabel.text = "🏥 \(type)"
            typeLabel.isHidden = false
        } else {
            typeLabel.text = nil
            typeLabel.isHidden = true
        }
        
        // Set hours
        if let hours = careCenter.dailyHours, !hours.isEmpty {
            hoursLabel.attributedText = formatDailyHoursAttributed(hours)
            hoursLabel.isHidden = false
        } else {
            hoursLabel.attributedText = nil
            hoursLabel.text = nil
            hoursLabel.isHidden = true
        }
        
        // Set phone number
        if let phone = careCenter.phoneNumber, !phone.isEmpty {
            phoneLabel.text = "📞 \(phone)"
            phoneLabel.isHidden = false
        } else {
            phoneLabel.text = nil
            phoneLabel.isHidden = true
        }
        
        // Set email
        if let email = careCenter.email, !email.isEmpty {
            emailLabel.text = "✉️ \(email)"
            emailLabel.isHidden = false
        } else {
            emailLabel.text = nil
            emailLabel.isHidden = true
        }
    }
    
    private func formatCapabilities(_ capabilities: [Capability]) -> String {
        let capabilityNames = capabilities.map { $0.name }
        return capabilityNames.joined(separator: " • ")
    }
    
    private func formatDailyHoursAttributed(_ hours: String) -> NSAttributedString {
        let emoji = "🕐 "
        let indent = "      " // 6 spaces to align with text after emoji
        
        // If it contains a comma, split by comma and format with proper alignment
        if hours.contains(",") {
            let components = hours.components(separatedBy: ",")
            let trimmedComponents = components.map { $0.trimmingCharacters(in: .whitespaces) }
            
            // Build the formatted string with emoji on first line and indent on subsequent lines
            var formattedText = emoji + trimmedComponents[0]
            for i in 1..<trimmedComponents.count {
                formattedText += "\n" + indent + trimmedComponents[i]
            }
            
            let attributedString = NSAttributedString(string: formattedText, attributes: [
                .font: UIFont.systemFont(ofSize: 15),
                .foregroundColor: UIColor.secondaryLabel
            ])
            return attributedString
        }
        
        // Otherwise return simple attributed string
        let fullText = emoji + hours
        let attributedString = NSAttributedString(string: fullText, attributes: [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.secondaryLabel
        ])
        return attributedString
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        addressLabel.text = nil
        capabilitiesLabel.text = nil
        typeLabel.text = nil
        hoursLabel.text = nil
        hoursLabel.attributedText = nil
        phoneLabel.text = nil
        emailLabel.text = nil
        capabilitiesLabel.isHidden = false
        typeLabel.isHidden = false
        hoursLabel.isHidden = false
        phoneLabel.isHidden = false
        emailLabel.isHidden = false
    }
}
