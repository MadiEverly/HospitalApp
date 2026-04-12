//
//  CareCenterTableViewCell.swift
//  HospitalApp
//
//  Created by Duane Homick on 2026-01-30.
//

import UIKit
import MapKit

class CareCenterTableViewCell: UITableViewCell {
    
    // MARK: - Display Style
    enum DisplayStyle {
        case timing          // default (used by CareCentersListViewController plural)
        case directionsButton // used by singular CareCenterListViewController
    }
    
    // MARK: - UI Components (Left column)
    private let nameLabel = UILabel()
    private let addressIconView = UIImageView()
    private let addressLabel = UILabel()
    private let capabilitiesLabel = UILabel()
    
    // Right column: labeled times
    private let rightStack = UIStackView()
    private var travelRow = UIStackView()
    private var waitRow = UIStackView()
    private var totalRow = UIStackView()
    private let travelTitleLabel = UILabel()
    private let travelValueLabel = UILabel()
    private let waitTitleLabel = UILabel()
    private let waitValueLabel = UILabel()
    private let totalTitleLabel = UILabel()
    private let totalValueLabel = UILabel()
    
    // Directions button (shown only in .directionsButton mode)
    private let directionsButton = UIButton(type: .system)

    // Wait-time pill (shown only in .directionsButton mode, under directionsButton)
    private let waitPill = PaddingLabel()
    private var waitPillTopConstraint: NSLayoutConstraint?

    // Travel-time pill (shown only in .directionsButton mode, under waitPill)
    private let travelPill = PaddingLabel()
    private var travelPillTopConstraint: NSLayoutConstraint?

    // MARK: - Properties
    static let reuseIdentifier = "CareCenterTableViewCell"

    private var currentCareCenterID: UUID?
    private var waitStatsObserver: NSObjectProtocol?
    private var adminWaitObserver: NSObjectProtocol?
    
    // Time state
    private var travelTimeSeconds: Int?
    private var waitTimeMinutes: Int?
    
    // Display mode
    private var displayStyle: DisplayStyle = .timing {
        didSet { applyDisplayStyle() }
    }
    
    // Destination info for directions
    private var destinationName: String?
    private var destinationCoordinate: CLLocationCoordinate2D?

    // Preferred formatting override (opt-in per controller)
    // When true, render times as "x hrs y min" instead of "H:MM".
    private var prefersLongTimeFormat = false

    // MARK: - Initialization
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        subscribeToWaitStats()
        subscribeToAdminWait()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        subscribeToWaitStats()
        subscribeToAdminWait()
    }
    
    deinit {
        if let obs = waitStatsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = adminWaitObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    private func subscribeToWaitStats() {
        waitStatsObserver = NotificationCenter.default.addObserver(forName: .waitStatsDidChange, object: nil, queue: .main) { [weak self] note in
            guard let self = self,
                  let careCenterID = self.currentCareCenterID else { return }
            // Only update if the notification pertains to this care center
            if let objectID = note.object as? UUID, objectID == careCenterID {
                if let stats = note.userInfo?["stats"] as? CareCenterWaitStats {
                    self.applyWait(stats: stats)
                } else if let cached = DataManager.shared.cachedEffectiveWaitStats(for: careCenterID) {
                    self.applyWait(stats: cached)
                }
            }
        }
    }

    private func subscribeToAdminWait() {
        adminWaitObserver = NotificationCenter.default.addObserver(forName: .adminWaitOverrideDidChange, object: nil, queue: .main) { [weak self] note in
            guard let self = self, let id = self.currentCareCenterID else { return }
            if let objectID = note.object as? UUID, objectID == id {
                // Pull effective stats again and apply
                Task { [weak self] in
                    guard let self else { return }
                    let stats = await DataManager.shared.effectiveWaitStats(careCenterID: id, force: false)
                    self.applyWait(stats: stats)
                }
            }
        }
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        selectionStyle = .default
        contentView.preservesSuperviewLayoutMargins = true
        
        // Left column
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 0
        
        addressIconView.translatesAutoresizingMaskIntoConstraints = false
        addressIconView.image = UIImage(systemName: "mappin.and.ellipse")
        addressIconView.tintColor = .systemRed
        addressIconView.contentMode = .scaleAspectFit
        
        addressLabel.translatesAutoresizingMaskIntoConstraints = false
        addressLabel.font = UIFont.systemFont(ofSize: 14)
        addressLabel.textColor = .secondaryLabel
        addressLabel.numberOfLines = 2
        addressLabel.lineBreakMode = .byTruncatingTail
        
        capabilitiesLabel.translatesAutoresizingMaskIntoConstraints = false
        capabilitiesLabel.font = UIFont.systemFont(ofSize: 13)
        capabilitiesLabel.textColor = .systemBlue
        capabilitiesLabel.numberOfLines = 0
        
        contentView.addSubview(nameLabel)
        contentView.addSubview(addressIconView)
        contentView.addSubview(addressLabel)
        contentView.addSubview(capabilitiesLabel)
        
        // Right column (stack of labeled rows)
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        rightStack.axis = .vertical
        rightStack.alignment = .trailing
        rightStack.spacing = 4
        contentView.addSubview(rightStack)
        
        // Configure rows
        func configureRow(titleLabel: UILabel, valueLabel: UILabel, title: String) -> UIStackView {
            titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
            titleLabel.textColor = .secondaryLabel
            titleLabel.text = title
            titleLabel.setContentHuggingPriority(.required, for: .horizontal)
            titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            
            valueLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            valueLabel.textColor = .label
            valueLabel.textAlignment = .right
            valueLabel.setContentHuggingPriority(.required, for: .horizontal)
            valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            
            let row = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 6
            return row
        }
        
        travelRow.translatesAutoresizingMaskIntoConstraints = false
        waitRow.translatesAutoresizingMaskIntoConstraints = false
        totalRow.translatesAutoresizingMaskIntoConstraints = false
        
        travelRow = configureRow(titleLabel: travelTitleLabel, valueLabel: travelValueLabel, title: "Travel")
        waitRow = configureRow(titleLabel: waitTitleLabel, valueLabel: waitValueLabel, title: "Wait")
        totalRow = configureRow(titleLabel: totalTitleLabel, valueLabel: totalValueLabel, title: "Total")
        
        rightStack.addArrangedSubview(travelRow)
        rightStack.addArrangedSubview(waitRow)
        rightStack.addArrangedSubview(totalRow)
        
        // Initial placeholders
        travelValueLabel.text = "—"
        waitValueLabel.text = "—"
        totalValueLabel.text = "—"
        
        // Directions button (hidden by default; shown in .directionsButton mode)
        directionsButton.translatesAutoresizingMaskIntoConstraints = false
        directionsButton.setTitle("Directions", for: .normal)
        directionsButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        directionsButton.setTitleColor(.white, for: .normal)
        directionsButton.backgroundColor = .systemBlue
        directionsButton.layer.cornerRadius = 8
        directionsButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        directionsButton.addTarget(self, action: #selector(directionsTapped), for: .touchUpInside)
        directionsButton.isHidden = true
        contentView.addSubview(directionsButton)

        // Wait-time pill
        waitPill.translatesAutoresizingMaskIntoConstraints = false
        waitPill.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        waitPill.textAlignment = .center
        waitPill.textColor = .white
        waitPill.layer.cornerRadius = 16
        waitPill.layer.masksToBounds = true
        waitPill.text = "No data"
        waitPill.backgroundColor = .tertiaryLabel
        waitPill.textInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        waitPill.isHidden = true
        contentView.addSubview(waitPill)

        // Travel-time pill (light grey with label-colored text)
        travelPill.translatesAutoresizingMaskIntoConstraints = false
        travelPill.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        travelPill.textAlignment = .center
        travelPill.textColor = .label
        travelPill.layer.cornerRadius = 16
        travelPill.layer.masksToBounds = true
        travelPill.text = "No ETA"
        travelPill.backgroundColor = .systemGray5
        travelPill.textInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        travelPill.isHidden = true
        contentView.addSubview(travelPill)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Right stack top-right
            rightStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            rightStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            rightStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
            
            // Directions button aligned where the right stack would be
            directionsButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            directionsButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Name label top-left
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -12),
            
            // Address row
            addressIconView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 8),
            addressIconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            addressIconView.widthAnchor.constraint(equalToConstant: 14),
            addressIconView.heightAnchor.constraint(equalToConstant: 14),
            
            addressLabel.centerYAnchor.constraint(equalTo: addressIconView.centerYAnchor),
            addressLabel.leadingAnchor.constraint(equalTo: addressIconView.trailingAnchor, constant: 6),
            addressLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -12),
            
            // Capabilities
            capabilitiesLabel.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: 6),
            capabilitiesLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            capabilitiesLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            capabilitiesLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            // Wait pill under the directions button
            waitPill.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            // Travel pill under wait pill
            travelPill.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            // Ensure cell grows to fit right column in both modes
            contentView.bottomAnchor.constraint(greaterThanOrEqualTo: rightStack.bottomAnchor, constant: 12),
            contentView.bottomAnchor.constraint(greaterThanOrEqualTo: travelPill.bottomAnchor, constant: 12)
        ])
        let pillTop = waitPill.topAnchor.constraint(equalTo: directionsButton.bottomAnchor, constant: 8)
        pillTop.isActive = true
        waitPillTopConstraint = pillTop

        let travelTop = travelPill.topAnchor.constraint(equalTo: waitPill.bottomAnchor, constant: 6)
        travelTop.isActive = true
        travelPillTopConstraint = travelTop
        
        // Start in default mode
        applyDisplayStyle()
    }
    
    private func applyDisplayStyle() {
        switch displayStyle {
        case .timing:
            rightStack.isHidden = false
            directionsButton.isHidden = true
            waitPill.isHidden = true
            travelPill.isHidden = true
            // Ensure left labels don't collide with hidden button
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -12).isActive = true
        case .directionsButton:
            rightStack.isHidden = true
            directionsButton.isHidden = false
            waitPill.isHidden = false
            travelPill.isHidden = false
            // Let left labels avoid the button
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: directionsButton.leadingAnchor, constant: -12).isActive = true
            // Refresh pill contents now that visible
            updateWaitPill(minutes: waitTimeMinutes)
            updateTravelPill(seconds: travelTimeSeconds)
        }
    }
    
    // MARK: - Public API
    func setDisplayStyle(_ style: DisplayStyle) {
        self.displayStyle = style
    }

    // Opt-in per controller: prefer "x hrs y min" formatting
    func setPreferredTimeFormatLong(_ enabled: Bool) {
        prefersLongTimeFormat = enabled
        // Re-apply current values to update text if needed
        if let t = travelTimeSeconds {
            travelValueLabel.text = formatted(fromSeconds: t)
        }
        if let w = waitTimeMinutes {
            waitValueLabel.text = formatted(fromMinutes: w)
        }
        updateTotal()
        updateWaitPill(minutes: waitTimeMinutes)
        updateTravelPill(seconds: travelTimeSeconds)
    }
    
    // MARK: - Configuration
    func configure(with careCenter: CareCenter, distance: Double?) {
        currentCareCenterID = careCenter.id

        // Left column
        nameLabel.text = careCenter.name
        addressLabel.text = careCenter.fullAddress
        capabilitiesLabel.text = formatCapabilities(careCenter.capabilities)
        
        // Keep destination info for directions
        destinationName = careCenter.name
        destinationCoordinate = CLLocationCoordinate2D(latitude: careCenter.latitude, longitude: careCenter.longitude)
        
        // Reset times
        travelTimeSeconds = nil
        waitTimeMinutes = nil
        travelValueLabel.text = "—"
        waitValueLabel.text = "—"
        totalValueLabel.text = "—"

        // Reset pills
        updateWaitPill(minutes: nil)
        updateTravelPill(seconds: nil)

        // Apply any cached effective stats immediately (admin or crowd)
        if let stats = DataManager.shared.cachedEffectiveWaitStats(for: careCenter.id) {
            applyWait(stats: stats)
        } else {
            // Fetch latest effective stats (admin returns immediately if available)
            Task { [weak self] in
                guard let self else { return }
                let stats = await DataManager.shared.effectiveWaitStats(careCenterID: careCenter.id, force: true)
                if self.currentCareCenterID == careCenter.id {
                    self.applyWait(stats: stats)
                }
            }
        }
    }
    
    // Called by controller once ETA has been computed
    func setTravelTime(seconds: Int) {
        travelTimeSeconds = seconds
        travelValueLabel.text = formatted(fromSeconds: seconds)
        updateTotal()
        updateTravelPill(seconds: seconds)
    }
    
    // Exposed in case you later want to set wait externally; currently we set from stats
    func setWaitTime(minutes: Int) {
        waitTimeMinutes = minutes
        waitValueLabel.text = formatted(fromMinutes: minutes)
        updateTotal()
        updateWaitPill(minutes: minutes)
    }
    
    private func applyWait(stats: CareCenterWaitStats) {
        // Treat <= 0 as no data
        if stats.averageMinutes > 0 {
            setWaitTime(minutes: stats.averageMinutes)
        } else {
            waitTimeMinutes = nil
            waitValueLabel.text = "—"
            updateTotal()
            updateWaitPill(minutes: nil)
        }
    }
    
    private func updateTotal() {
        guard let travel = travelTimeSeconds, let waitMin = waitTimeMinutes else {
            totalValueLabel.text = "—"
            return
        }
        let totalSeconds = travel + waitMin * 60
        totalValueLabel.text = formatted(fromSeconds: totalSeconds)
    }
    
    private func formatCapabilities(_ capabilities: [Capability]) -> String {
        let maxDisplay = 3
        let displayCapabilities = capabilities.prefix(maxDisplay)
        let names = displayCapabilities.map { $0.name }
        var result = names.joined(separator: " • ")
        if capabilities.count > maxDisplay {
            result += " +\(capabilities.count - maxDisplay)"
        }
        return result
    }
    
    // MARK: - Formatting
    // Controller-selectable formatter
    private func formatted(fromSeconds seconds: Int) -> String {
        let totalMinutes = max(0, Int(round(Double(seconds) / 60.0)))
        return formatted(fromMinutes: totalMinutes)
    }
    
    private func formatted(fromMinutes minutes: Int) -> String {
        if prefersLongTimeFormat {
            return formatHoursMinutesShortPlural(fromMinutes: minutes)
        } else {
            return formatHMM(fromMinutes: minutes)
        }
    }

    // Existing H:MM formatter (kept for default)
    private func formatHMM(fromMinutes minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 {
            return "\(h):" + String(format: "%02d", m)
        } else {
            return "0:" + String(format: "%02d", m)
        }
    }

    // Existing long formatter used by pill (kept)
    private func formatHoursMinutesLong(fromMinutes minutes: Int) -> String {
        let clamped = max(0, minutes)
        let hours = clamped / 60
        let mins = clamped % 60
        switch (hours, mins) {
        case (0, let m):
            return "\(m) min"
        case (let h, 0):
            return "\(h) hr"
        default:
            return "\(hours) hr \(mins) min"
        }
    }

    // New short pluralized formatter: "x hrs y min"
    private func formatHoursMinutesShortPlural(fromMinutes minutes: Int) -> String {
        let clamped = max(0, minutes)
        let hours = clamped / 60
        let mins = clamped % 60
        if hours == 0 {
            return "\(mins) min"
        } else if mins == 0 {
            // Always "hrs" per request (no singular special-case)
            return "\(hours) hrs"
        } else {
            return "\(hours) hrs \(mins) min"
        }
    }

    // MARK: - Pills content/color with icons
    private func updateWaitPill(minutes: Int?) {
        // Always set content/color; visibility is handled by display style
        guard let mins = minutes, mins > 0 else {
            waitPill.attributedText = pillText(iconSystemName: "clock", text: "No data", textColor: .white)
            waitPill.backgroundColor = .tertiaryLabel
            return
        }

        // Singular list thresholds:
        // 1–120 min: green
        // 121–240 min: yellow
        // 241+ min: red
        let color: UIColor
        if mins <= 120 {
            color = .systemGreen
        } else if mins <= 240 {
            color = .systemYellow
        } else {
            color = .systemRed
        }
        let text = formatHoursMinutesLong(fromMinutes: mins)
        waitPill.attributedText = pillText(iconSystemName: "clock", text: text, textColor: .white)
        waitPill.backgroundColor = color
    }

    private func updateTravelPill(seconds: Int?) {
        // Light grey pill with label-colored text/icon
        let textColor: UIColor = .label
        let bgColor: UIColor = .systemGray5

        guard let secs = seconds, secs > 0 else {
            travelPill.attributedText = pillText(iconSystemName: "car.fill", text: "No ETA", textColor: textColor)
            travelPill.backgroundColor = bgColor
            return
        }
        let mins = max(1, Int(round(Double(secs) / 60.0)))
        let text = formatHoursMinutesLong(fromMinutes: mins)
        travelPill.attributedText = pillText(iconSystemName: "car.fill", text: text, textColor: textColor)
        travelPill.backgroundColor = bgColor
    }

    private func pillText(iconSystemName: String, text: String, textColor: UIColor) -> NSAttributedString {
        let attachment = NSTextAttachment()
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let image = UIImage(systemName: iconSystemName, withConfiguration: config)?.withTintColor(textColor, renderingMode: .alwaysOriginal)
        attachment.image = image
        // Raise slightly to align with text baseline
        attachment.bounds = CGRect(x: 0, y: -1, width: 16, height: 16)

        let iconString = NSAttributedString(attachment: attachment)
        let spacer = NSAttributedString(string: " ")
        let textString = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: textColor
        ])
        let result = NSMutableAttributedString()
        result.append(iconString)
        result.append(spacer)
        result.append(textString)
        return result
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        addressLabel.text = nil
        capabilitiesLabel.text = nil
        currentCareCenterID = nil
        travelTimeSeconds = nil
        waitTimeMinutes = nil
        travelValueLabel.text = "—"
        waitValueLabel.text = "—"
        totalValueLabel.text = "—"
        destinationName = nil
        destinationCoordinate = nil
        // Reset pill content; visibility is controlled by display style
        waitPill.attributedText = pillText(iconSystemName: "clock", text: "No data", textColor: .white)
        waitPill.backgroundColor = .tertiaryLabel
        waitPill.isHidden = true

        travelPill.attributedText = pillText(iconSystemName: "car.fill", text: "No ETA", textColor: .label)
        travelPill.backgroundColor = .systemGray5
        travelPill.isHidden = true

        // Reset to default style for safety (plural controller expectation)
        displayStyle = .timing
        prefersLongTimeFormat = false
        applyDisplayStyle()
    }
    
    // MARK: - Actions
    @objc private func directionsTapped() {
        guard let coord = destinationCoordinate else { return }
        let name = destinationName ?? "Destination"
        
        // Prefer Google Maps if installed
        let lat = coord.latitude
        let lon = coord.longitude
        if let gmURL = URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving"),
           UIApplication.shared.canOpenURL(gmURL) {
            UIApplication.shared.open(gmURL, options: [:], completionHandler: nil)
            return
        }
        
        // Fallback to Apple Maps
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        destination.name = name
        destination.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

// Small padding label subclass for pill (kept for reuse)
final class PaddingLabel: UILabel {
    var textInsets: UIEdgeInsets = .zero {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        let insets = textInsets
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }
}

