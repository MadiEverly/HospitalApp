//
//  CareCenterDetailsViewController.swift
//  HospitalApp
//
//  Created by Duane Homick on 2026-01-28.
//

import UIKit
import MapKit
import CoreLocation

class CareCenterDetailsViewController: UIViewController {

    // MARK: - Properties
    var careCenter: CareCenter?
    // Optional user coordinate passed by caller to avoid re-requesting location
    var userCoordinate: CLLocationCoordinate2D?
    
    private let closeButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)

    // Stats header UI
    private let statsContainer = UIView()
    private let avgPill = PaddingLabel()
    private let statsLabel = UILabel()
    private let reportButton = UIButton(type: .system)
    private let facilityReportButton = UIButton(type: .system)

    private var waitStatsObserver: NSObjectProtocol?
    private var issuesObserver: NSObjectProtocol?
    private var adminWaitObserver: NSObjectProtocol?
    private var adminFacilityObserver: NSObjectProtocol?
    
    // Travel time
    private var travelTimeSeconds: Int?
    private let locationManager = CLLocationManager()

    // Facility issues
    private var facilityIssues: [FacilityIssue] = []
    private var adminFacilityOverride: AdminFacilityIssueOverride?

    // Softer lilac color for admin-set wait times
    private let adminLilacColor = UIColor(red: 0.78, green: 0.64, blue: 0.86, alpha: 1.0)

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.layer.backgroundColor = UIColor.white.cgColor
        // Important: add and constrain stats header before tableView that depends on it
        setupStatsHeader()
        setupTableView()
        setupCloseButton()
        // Ensure close button is on top of everything
        view.bringSubviewToFront(closeButton)
        subscribeToWaitStats()
        subscribeToFacilityIssues()
        subscribeToAdminOverrides()
        refreshAll()
        computeTravelTimeIfPossible()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Keep close button above other subviews after layout passes
        view.bringSubviewToFront(closeButton)
    }

    deinit {
        if let obs = waitStatsObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = issuesObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = adminWaitObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = adminFacilityObserver { NotificationCenter.default.removeObserver(obs) }
    }
    
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(CareCenterDetailHeaderCell.self, forCellReuseIdentifier: CareCenterDetailHeaderCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "IssueCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AdminNoticeCell")
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            // Place the table below the stats container
            tableView.topAnchor.constraint(equalTo: statsContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupCloseButton() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: symbolConfig), for: .normal)
        closeButton.tintColor = .black
        closeButton.backgroundColor = .systemGray5
        closeButton.layer.cornerRadius = 20
        closeButton.layer.masksToBounds = true
        // Enlarge tap target slightly
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        closeButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12)
        ])

        // Ensure the stats text doesn't extend under the close button
        NSLayoutConstraint.activate([
            statsLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12)
        ])
    }

    private func setupStatsHeader() {
        statsContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statsContainer)

        // Avg pill
        avgPill.translatesAutoresizingMaskIntoConstraints = false
        avgPill.font = UIFont.systemFont(ofSize: 16, weight: .bold) // slightly smaller to avoid squishing
        avgPill.adjustsFontSizeToFitWidth = true
        avgPill.minimumScaleFactor = 0.9
        avgPill.textAlignment = .center
        avgPill.textColor = .white
        avgPill.layer.cornerRadius = 20
        avgPill.layer.masksToBounds = true
        avgPill.text = "—"
        avgPill.backgroundColor = UIColor.tertiaryLabel
        // Add internal padding so text isn't flush to the edges
        avgPill.textInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        // Make the pill resist being squished
        avgPill.setContentCompressionResistancePriority(.required, for: .horizontal)
        avgPill.setContentHuggingPriority(.required, for: .horizontal)
        statsContainer.addSubview(avgPill)

        // Stats label
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        statsLabel.font = UIFont.systemFont(ofSize: 14)
        statsLabel.textColor = .secondaryLabel
        statsLabel.numberOfLines = 2
        statsContainer.addSubview(statsLabel)

        // Report wait button
        reportButton.translatesAutoresizingMaskIntoConstraints = false
        reportButton.setTitle("Report wait time", for: .normal)
        reportButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        reportButton.backgroundColor = .systemBlue
        reportButton.tintColor = .white
        reportButton.layer.cornerRadius = 8
        reportButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        reportButton.addTarget(self, action: #selector(reportTapped), for: .touchUpInside)
        statsContainer.addSubview(reportButton)

        // Report facility issue button
        facilityReportButton.translatesAutoresizingMaskIntoConstraints = false
        facilityReportButton.setTitle("Report facility issue", for: .normal)
        facilityReportButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        facilityReportButton.backgroundColor = .systemOrange
        facilityReportButton.tintColor = .white
        facilityReportButton.layer.cornerRadius = 8
        facilityReportButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        facilityReportButton.addTarget(self, action: #selector(reportFacilityTapped), for: .touchUpInside)
        statsContainer.addSubview(facilityReportButton)

        NSLayoutConstraint.activate([
            statsContainer.topAnchor.constraint(equalTo: view.topAnchor),
            statsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statsContainer.heightAnchor.constraint(equalToConstant: 150),

            avgPill.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            avgPill.topAnchor.constraint(equalTo: statsContainer.topAnchor, constant: 20),
            avgPill.heightAnchor.constraint(equalToConstant: 40),
            // width can grow with content; keep a reasonable minimum
            avgPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),

            statsLabel.leadingAnchor.constraint(equalTo: avgPill.trailingAnchor, constant: 12),
            statsLabel.centerYAnchor.constraint(equalTo: avgPill.centerYAnchor),
            statsLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),

            reportButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            reportButton.topAnchor.constraint(equalTo: avgPill.bottomAnchor, constant: 12),

            facilityReportButton.leadingAnchor.constraint(equalTo: reportButton.trailingAnchor, constant: 12),
            facilityReportButton.centerYAnchor.constraint(equalTo: reportButton.centerYAnchor),
            facilityReportButton.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
        ])
    }

    private func subscribeToWaitStats() {
        waitStatsObserver = NotificationCenter.default.addObserver(forName: .waitStatsDidChange, object: nil, queue: .main) { [weak self] note in
            guard let self = self,
                  let careCenter = self.careCenter else { return }
            if let objectID = note.object as? UUID, objectID == careCenter.id {
                if let stats = note.userInfo?["stats"] as? CareCenterWaitStats {
                    self.applyStats(stats)
                } else if let cached = DataManager.shared.cachedEffectiveWaitStats(for: careCenter.id) {
                    self.applyStats(cached)
                }
            }
        }
    }

    private func subscribeToFacilityIssues() {
        issuesObserver = NotificationCenter.default.addObserver(forName: .facilityIssuesDidChange, object: nil, queue: .main) { [weak self] note in
            guard let self = self,
                  let center = self.careCenter else { return }
            if let objectID = note.object as? UUID, objectID == center.id {
                if let issues = note.userInfo?["issues"] as? [FacilityIssue] {
                    self.facilityIssues = issues
                    self.tableView.reloadData()
                } else if let cached = DataManager.shared.cachedEffectiveFacilityIssues(for: center.id) {
                    self.facilityIssues = cached
                    self.tableView.reloadData()
                }
            }
        }
    }

    private func subscribeToAdminOverrides() {
        adminWaitObserver = NotificationCenter.default.addObserver(forName: .adminWaitOverrideDidChange, object: nil, queue: .main) { [weak self] note in
            guard let self = self, let center = self.careCenter else { return }
            if let objectID = note.object as? UUID, objectID == center.id {
                // Pull effective stats again and apply
                Task { [weak self] in
                    guard let self else { return }
                    let stats = await DataManager.shared.effectiveWaitStats(careCenterID: center.id, force: false)
                    self.applyStats(stats)
                }
            }
        }
        adminFacilityObserver = NotificationCenter.default.addObserver(forName: .adminFacilityOverrideDidChange, object: nil, queue: .main) { [weak self] note in
            guard let self = self, let center = self.careCenter else { return }
            if let objectID = note.object as? UUID, objectID == center.id {
                self.adminFacilityOverride = (note.userInfo?["override"] as? AdminFacilityIssueOverride)
                self.tableView.reloadData()
            }
        }
    }

    private func refreshAll() {
        refreshStats()
        refreshFacilityIssues()
        // Load current admin facility override into memory (from DataManager cache via notification or direct cache read)
        if let center = careCenter {
            // There is no direct accessor; rely on latest notification or re-trigger issues change
        }
    }

    private func refreshStats() {
        guard let careCenter = careCenter else { return }
        // Try effective cached first
        if let cached = DataManager.shared.cachedEffectiveWaitStats(for: careCenter.id) {
            applyStats(cached)
        }
        // Fetch latest effective
        Task { [weak self] in
            guard let self else { return }
            let stats = await DataManager.shared.effectiveWaitStats(careCenterID: careCenter.id, force: true)
            self.applyStats(stats)
        }
    }

    private func refreshFacilityIssues() {
        guard let center = careCenter else { return }
        if let cached = DataManager.shared.cachedEffectiveFacilityIssues(for: center.id) {
            self.facilityIssues = cached.sorted { $0.isVerified && !$1.isVerified }
            tableView.reloadData()
        }
        Task { [weak self] in
            guard let self else { return }
            let issues = await DataManager.shared.effectiveFacilityIssues(careCenterID: center.id, force: true)
            self.facilityIssues = issues
            self.tableView.reloadData()
        }
    }

    private func applyStats(_ stats: CareCenterWaitStats) {
        // Determine if admin override is active by comparing stats.reportsCount==0 and checking DataManager cache
        let isAdmin = isAdminOverrideActive(for: stats.careCenterID, minutes: stats.averageMinutes)

        if stats.reportsCount == 0 && stats.averageMinutes <= 0 && !isAdmin {
            avgPill.text = "No data"
            avgPill.backgroundColor = UIColor.tertiaryLabel
            statsLabel.text = "No recent reports (last 4h)"
            return
        }

        let formatted = formatHoursMinutes(fromMinutes: stats.averageMinutes)
        avgPill.text = formatted + (isAdmin ? " (Admin)" : "")
        let bucket = WaitTimeColorBucket.bucket(for: stats.averageMinutes)
        avgPill.backgroundColor = isAdmin ? adminLilacColor : bucket.color

        let updatedAgo = formatUpdatedAgo(stats.lastUpdated)
        if isAdmin {
            statsLabel.text = "Admin-set wait time • Updated \(updatedAgo)"
        } else {
            statsLabel.text = "Avg \(stats.averageMinutes) min • \(stats.reportsCount) reports (last 4h)\nUpdated \(updatedAgo)"
        }
    }

    private func formatHoursMinutes(fromMinutes minutes: Int) -> String {
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

    private func isAdminOverrideActive(for careCenterID: UUID, minutes: Int) -> Bool {
        if let eff = DataManager.shared.cachedEffectiveWaitStats(for: careCenterID) {
            return eff.averageMinutes == minutes && eff.reportsCount == 0 && minutes > 0
        }
        return false
    }

    private func formatUpdatedAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }

    @objc private func reportTapped() {
        guard let careCenter = careCenter else { return }
        presentReportSheet(for: careCenter)
    }

    @objc private func reportFacilityTapped() {
        guard let center = careCenter else { return }
        let vc = FacilityIssueReportViewController(careCenterID: center.id)
        present(vc, animated: true)
    }

    private func presentReportSheet(for careCenter: CareCenter) {
        let alert = UIAlertController(title: "Report wait time", message: nil, preferredStyle: .alert)

        // Embed custom content in a child view controller (supported way)
        let contentVC = SliderContentViewController(initialValue: 30, min: 0, max: 180)
        alert.setValue(contentVC, forKey: "contentViewController")

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Submit", style: .default, handler: { [weak self, weak contentVC] _ in
            guard let minutes = contentVC?.currentValue else { return }
            Task {
                do {
                    try await DataManager.shared.submitWaitTime(careCenterID: careCenter.id, minutes: minutes)
                    self?.showToast("Thanks! Your report was submitted.")
                } catch {
                    self?.showToast(error.localizedDescription)
                }
            }
        }))

        present(alert, animated: true, completion: nil)
    }

    private func showToast(_ message: String) {
        let toast = UILabel()
        toast.text = message
        toast.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        toast.textColor = .white
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toast.textAlignment = .center
        toast.numberOfLines = 0
        toast.layer.cornerRadius = 8
        toast.layer.masksToBounds = true

        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            toast.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.9)
        ])
        toast.alpha = 0
        UIView.animate(withDuration: 0.25, animations: {
            toast.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.25, delay: 1.5, options: [], animations: {
                toast.alpha = 0
            }, completion: { _ in
                toast.removeFromSuperview()
            })
        }
    }
    
    // MARK: - Travel time (ETA)
    
    private func computeTravelTimeIfPossible() {
        guard let center = careCenter else { return }
        
        // If caller provided a user coordinate, use it
        if let origin = userCoordinate {
            calculateETA(from: origin, to: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude))
            return
        }
        
        // Otherwise, attempt to use our own location manager
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        switch status {
        case .notDetermined:
            locationManager.delegate = self
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.delegate = self
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }
    
    private func calculateETA(from origin: CLLocationCoordinate2D, to dest: CLLocationCoordinate2D) {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        
        MKDirections(request: request).calculateETA { [weak self] response, _ in
            guard let self = self else { return }
            if let eta = response?.expectedTravelTime, eta > 0 {
                self.travelTimeSeconds = Int(eta)
                // Update the single header cell
                if let cell = self.tableView.visibleCells.first(where: { $0 is CareCenterDetailHeaderCell }) as? CareCenterDetailHeaderCell,
                   let secs = self.travelTimeSeconds {
                    cell.setTravelTime(seconds: secs)
                } else {
                    self.tableView.reloadData()
                }
            }
        }
    }

    @objc private func dismissSelf() {
        dismiss(animated: true, completion: nil)
    }
}

private struct AssociatedKeys {
    static var valueLabelKey = "valueLabelKey"
}

// Simple content VC to host slider + live value label + numeric input safely inside UIAlertController
private final class SliderContentViewController: UIViewController, UITextFieldDelegate {
    private let slider = UISlider(frame: .zero)
    private let valueLabel = UILabel(frame: .zero)
    private let minuteField = UITextField(frame: .zero)
    private let minValue: Float
    private let maxValue: Float
    private(set) var currentValue: Int

    init(initialValue: Int, min: Int, max: Int) {
        self.currentValue = initialValue
        self.minValue = Float(min)
        self.maxValue = Float(max)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.translatesAutoresizingMaskIntoConstraints = false

        // Slider
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = minValue
        slider.maximumValue = maxValue
        slider.value = Float(currentValue)
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)

        // Value label
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.textAlignment = .left
        valueLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        valueLabel.textColor = .secondaryLabel
        valueLabel.text = "\(currentValue) min"

        // Numeric input
        minuteField.translatesAutoresizingMaskIntoConstraints = false
        minuteField.borderStyle = .roundedRect
        minuteField.keyboardType = .numberPad
        minuteField.placeholder = "Minutes"
        minuteField.textAlignment = .right
        minuteField.font = UIFont.systemFont(ofSize: 15)
        minuteField.text = "\(currentValue)"
        minuteField.delegate = self
        minuteField.addTarget(self, action: #selector(textFieldEditingChanged(_:)), for: .editingChanged)

        // Add toolbar with Done button to dismiss number pad
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(doneTapped))
        toolbar.items = [flex, done]
        minuteField.inputAccessoryView = toolbar

        view.addSubview(slider)
        view.addSubview(valueLabel)
        view.addSubview(minuteField)

        NSLayoutConstraint.activate([
            slider.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            slider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            valueLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 8),
            valueLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: minuteField.leadingAnchor, constant: -8),
            valueLabel.heightAnchor.constraint(equalToConstant: 20),

            minuteField.centerYAnchor.constraint(equalTo: valueLabel.centerYAnchor),
            minuteField.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            minuteField.widthAnchor.constraint(equalToConstant: 80),
            minuteField.heightAnchor.constraint(equalToConstant: 34),

            minuteField.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        let rounded = Int(round(sender.value))
        applyNewValue(rounded, source: .slider)
    }

    @objc private func textFieldEditingChanged(_ sender: UITextField) {
        // Parse integer, clamp to range, update UI
        let digits = sender.text?.filter { $0.isNumber } ?? ""
        the: if let parsed = Int(digits) {
            let clamped = max(Int(minValue), min(Int(maxValue), parsed))
            if "\(clamped)" != sender.text {
                sender.text = "\(clamped)"
            }
            applyNewValue(clamped, source: .textField)
        } else {
            // keep previous value visible
            sender.text = "\(currentValue)"
            break the
        }
    }

    @objc private func doneTapped() {
        view.endEditing(true)
    }

    private enum ChangeSource { case slider, textField }

    private func applyNewValue(_ newValue: Int, source: ChangeSource) {
        guard newValue != currentValue else {
            valueLabel.text = "\(currentValue) min"
            return
        }
        currentValue = newValue
        valueLabel.text = "\(currentValue) min"

        switch source {
        case .slider:
            minuteField.text = "\(currentValue)"
        case .textField:
            slider.value = Float(currentValue)
        }
    }

    // Only allow digits in the text field
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string.isEmpty { return true } // deletion
        return string.allSatisfy { $0.isNumber }
    }

    // Give UIAlertController a reasonable intrinsic size for the content
    override var preferredContentSize: CGSize {
        get { CGSize(width: 250, height: 110) }
        set { super.preferredContentSize = newValue }
    }
}

// MARK: - UITableViewDataSource
extension CareCenterDetailsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        // Section 0: header cell, Section 1: admin notice (0 or 1), Section 2: facility issues
        return 3
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return careCenter != nil ? 1 : 0
        case 1:
            return adminFacilityOverride == nil ? 0 : 1
        case 2:
            return facilityIssues.count
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        if indexPath.section == 0 {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: CareCenterDetailHeaderCell.reuseIdentifier, for: indexPath) as? CareCenterDetailHeaderCell,
                  let careCenter = careCenter else {
                return UITableViewCell()
            }
            cell.configure(with: careCenter)
            if let secs = travelTimeSeconds {
                cell.setTravelTime(seconds: secs)
            }
            return cell
        } else if indexPath.section == 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "AdminNoticeCell", for: indexPath)
            cell.selectionStyle = .none
            cell.contentView.backgroundColor = UIColor.secondarySystemBackground
            var content = UIListContentConfiguration.subtitleCell()
            if let override = adminFacilityOverride {
                content.text = "Admin Notice: \(override.title)"
                let updated = formatUpdatedAgo(override.updatedAt)
                var secondary = override.message
                if let by = override.updatedBy, !by.isEmpty {
                    secondary += "\nUpdated \(updated) by \(by)"
                } else {
                    secondary += "\nUpdated \(updated)"
                }
                content.secondaryText = secondary
                content.textProperties.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
                content.textProperties.color = override.severity.color
                content.secondaryTextProperties.color = .label
            } else {
                content.text = "Admin Notice"
                content.secondaryText = ""
            }
            cell.contentConfiguration = content
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "IssueCell", for: indexPath)
            let issue = facilityIssues[indexPath.row]
            cell.textLabel?.numberOfLines = 0
            cell.detailTextLabel?.numberOfLines = 0

            var content = UIListContentConfiguration.subtitleCell()
            content.text = issue.titleLine
            content.secondaryText = issue.statusLine
            content.textProperties.font = UIFont.systemFont(ofSize: 15, weight: issue.isVerified ? .semibold : .regular)
            content.secondaryTextProperties.color = issue.isVerified ? .systemGreen : .secondaryLabel
            cell.contentConfiguration = content

            // Add a subtle separator look
            cell.selectionStyle = .none
            return cell
        }
    }
}

// MARK: - UITableViewDelegate
extension CareCenterDetailsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.section {
        case 0: return 300
        case 1: return 88
        default: return 56
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 2:
            return facilityIssues.isEmpty ? nil : "Facility Issues"
        default:
            return nil
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension CareCenterDetailsViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        guard let center = careCenter else { return }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            // No location -> no ETA
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last?.coordinate,
              let center = careCenter else { return }
        manager.stopUpdatingLocation()
        calculateETA(from: loc, to: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude))
    }
}
