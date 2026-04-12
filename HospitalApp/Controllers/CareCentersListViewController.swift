//  ViewController.swift
//  HospitalApp
//
//  Created by Duane Homick on 2026-01-28.
//

import UIKit
import CoreLocation
import MapKit

class CareCentersListViewController: UIViewController {

    // MARK: - Properties
    var filterCapability: Capability?
    var onCareCenterSelected: ((CareCenter) -> Void)?
    private var careCenters: [CareCenter] = []
    // Track ETA per center
    private var careCentersWithETA: [(careCenter: CareCenter, eta: TimeInterval?)] = []
    private let tableView = UITableView()
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    // Header elements (only filter header inside tableHeaderView)
    private let headerContainer = UIView()
    private let filterHeaderLabel = UILabel()
    private let filterButton = UIButton(type: .system)
    private let sortButton = UIButton(type: .system)
    private var careCentersObserver: NSObjectProtocol?
    
    // ETA cache to avoid repeated MKDirections calls
    private var etaCache: [UUID: TimeInterval] = [:]
    private var etaRequestsInFlight: Set<UUID> = []

    // Wait stats cache for sorting (minutes-only here)
    private var waitMinutesCache: [UUID: Int?] = [:]

    // Sort mode
    private enum SortMode {
        case total
        case travel
        case wait
    }
    private var currentSortMode: SortMode = .total {
        didSet {
            applyCurrentSort()
            updateSortButtonTitle()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        
        setupLocationManager()
        setupTableView()
        setupTableHeaderView()
        
        // If a filter capability was passed, use it to filter the care centers
        if let capability = filterCapability {
            loadFilteredCareCenters(by: capability)
        } else {
            loadAllCareCenters()
        }
        
        // Observe care center changes from DataManager
        careCentersObserver = NotificationCenter.default.addObserver(forName: .careCentersDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            if let capability = self.filterCapability {
                self.loadFilteredCareCenters(by: capability)
            } else {
                self.loadAllCareCenters()
            }
            // Clear ETAs as dataset changed
            self.etaCache.removeAll()
            self.etaRequestsInFlight.removeAll()
            self.tableView.reloadData()
            // Kick off ETA calculations again if we have location
            self.requestETAsForAllIfPossible()
        }
    }
    
    deinit {
        if let obs = careCentersObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // Get current location if authorized
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }
    
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(CareCenterTableViewCell.self, forCellReuseIdentifier: CareCenterTableViewCell.reuseIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        tableView.separatorStyle = .singleLine
        tableView.backgroundColor = .systemBackground
        
        view.addSubview(tableView)
        
        // Table view fills the view; header is now tableHeaderView
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupTableHeaderView() {
        // Container view that will become tableHeaderView
        let container = UIView()
        container.backgroundColor = .systemBackground
        
        // Filter header label
        filterHeaderLabel.translatesAutoresizingMaskIntoConstraints = false
        filterHeaderLabel.text = filterCapability?.name ?? "All Care Centers"
        filterHeaderLabel.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        filterHeaderLabel.textColor = .label
        filterHeaderLabel.numberOfLines = 1
        container.addSubview(filterHeaderLabel)
        
        // Filter button (top-right)
        filterButton.translatesAutoresizingMaskIntoConstraints = false
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let funnel = UIImage(systemName: "line.3.horizontal.decrease.circle", withConfiguration: symbolConfig)
        filterButton.setImage(funnel, for: .normal)
        filterButton.setTitle(" Filter", for: .normal)
        filterButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        filterButton.tintColor = .systemBlue
        filterButton.addTarget(self, action: #selector(didTapFilter), for: .touchUpInside)
        filterButton.setContentHuggingPriority(.required, for: .horizontal)
        filterButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        container.addSubview(filterButton)

        // Sort button (to the left of filter button)
        sortButton.translatesAutoresizingMaskIntoConstraints = false
        let sortIcon = UIImage(systemName: "arrow.up.arrow.down.circle", withConfiguration: symbolConfig)
        sortButton.setImage(sortIcon, for: .normal)
        sortButton.setTitle(" Sort", for: .normal)
        sortButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        sortButton.tintColor = .systemBlue
        sortButton.addTarget(self, action: #selector(didTapSort), for: .touchUpInside)
        sortButton.setContentHuggingPriority(.required, for: .horizontal)
        sortButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        container.addSubview(sortButton)
        updateSortButtonTitle()
        
        // Separator
        let separatorLine = UIView()
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        separatorLine.backgroundColor = .separator
        container.addSubview(separatorLine)
        
        // Prepare initial frame; height will be adjusted after layout
        let width = view.bounds.width
        container.frame = CGRect(x: 0, y: 0, width: width, height: 1)
        
        NSLayoutConstraint.activate([
            filterHeaderLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            filterHeaderLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            // Constrain trailing to sort button with spacing
            filterHeaderLabel.trailingAnchor.constraint(lessThanOrEqualTo: sortButton.leadingAnchor, constant: -8),
            
            // Sort button to the left of filter button
            sortButton.centerYAnchor.constraint(equalTo: filterHeaderLabel.centerYAnchor),
            sortButton.trailingAnchor.constraint(equalTo: filterButton.leadingAnchor, constant: -12),
            
            // Filter button pinned to trailing
            filterButton.centerYAnchor.constraint(equalTo: filterHeaderLabel.centerYAnchor),
            filterButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            
            separatorLine.topAnchor.constraint(equalTo: filterHeaderLabel.bottomAnchor, constant: 12),
            separatorLine.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 0.5),
            separatorLine.bottomAnchor.constraint(equalTo: container.bottomAnchor) // defines container height
        ])
        
        // Force layout to compute the proper intrinsic height
        container.setNeedsLayout()
        container.layoutIfNeeded()
        // Make sure the header uses the computed height
        var headerFrame = container.frame
        headerFrame.size.height = separatorLine.frame.maxY
        container.frame = headerFrame
        
        tableView.tableHeaderView = container
    }
    
    // MARK: - Data Loading
    
    private func loadAllCareCenters() {
        careCenters = DataManager.shared.readAll()
        resetETAModel()
        Task { await self.updateWaitMinutesAndResort() }
        tableView.reloadData()
        requestETAsForAllIfPossible()
        // Update filter header text
        filterHeaderLabel.text = "All Care Centers"
        applyCurrentSort()
        refreshHeaderSizeIfNeeded()
        print("Loaded \(careCenters.count) care centers")
    }
    
    private func loadFilteredCareCenters(by capability: Capability) {
        careCenters = DataManager.shared.filter(byCapability: capability)
        resetETAModel()
        Task { await self.updateWaitMinutesAndResort() }
        tableView.reloadData()
        requestETAsForAllIfPossible()
        // Update filter header text
        filterHeaderLabel.text = capability.name
        applyCurrentSort()
        refreshHeaderSizeIfNeeded()
        print("Filtered by \(capability.name): \(careCenters.count) care centers")
    }
    
    private func resetETAModel() {
        // Initialize list with any cached ETA
        careCentersWithETA = careCenters.map { ($0, etaCache[$0.id]) }
        // Sort by current mode
        applyCurrentSort()
    }
    
    // MARK: - Total/wait/travel sorting helpers
    
    private func totalSeconds(for centerID: UUID) -> Int? {
        guard let waitMins = waitMinutesCache[centerID] ?? nil,
              let eta = etaCache[centerID] else {
            return nil
        }
        let mins = max(0, waitMins)
        let etaInt = max(0, Int(eta))
        return mins * 60 + etaInt
    }
    
    private func sortCareCentersByTotalTime() {
        careCentersWithETA.sort { lhs, rhs in
            let lTotal = totalSeconds(for: lhs.careCenter.id)
            let rTotal = totalSeconds(for: rhs.careCenter.id)
            switch (lTotal, rTotal) {
            case let (l?, r?):
                if l != r { return l < r }
                return lhs.careCenter.name < rhs.careCenter.name
            case (nil, nil):
                let lIndex = careCenters.firstIndex(where: { $0.id == lhs.careCenter.id }) ?? 0
                let rIndex = careCenters.firstIndex(where: { $0.id == rhs.careCenter.id }) ?? 0
                return lIndex < rIndex
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }
    }

    private func sortByTravelETA() {
        careCentersWithETA.sort { lhs, rhs in
            switch (etaCache[lhs.careCenter.id], etaCache[rhs.careCenter.id]) {
            case let (l?, r?):
                if l != r { return l < r }
                return lhs.careCenter.name < rhs.careCenter.name
            case (nil, nil):
                let lIndex = careCenters.firstIndex(where: { $0.id == lhs.careCenter.id }) ?? 0
                let rIndex = careCenters.firstIndex(where: { $0.id == rhs.careCenter.id }) ?? 0
                return lIndex < rIndex
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }
    }

    private func sortByWaitMinutes() {
        careCentersWithETA.sort { lhs, rhs in
            let lWait = waitMinutesCache[lhs.careCenter.id] ?? nil
            let rWait = waitMinutesCache[rhs.careCenter.id] ?? nil
            switch (lWait, rWait) {
            case let (l?, r?):
                if l != r { return l < r }
                return lhs.careCenter.name < rhs.careCenter.name
            case (nil, nil):
                let lIndex = careCenters.firstIndex(where: { $0.id == lhs.careCenter.id }) ?? 0
                let rIndex = careCenters.firstIndex(where: { $0.id == rhs.careCenter.id }) ?? 0
                return lIndex < rIndex
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }
    }

    private func applyCurrentSort() {
        switch currentSortMode {
        case .total:
            sortCareCentersByTotalTime()
        case .travel:
            sortByTravelETA()
        case .wait:
            sortByWaitMinutes()
        }
        tableView.reloadData()
    }
    
    private func requestETAsForAllIfPossible() {
        guard currentLocation != nil else { return }
        for item in careCentersWithETA {
            requestETAIfNeeded(for: item.careCenter)
        }
    }

    // MARK: - Wait minutes fetch and resort

    private func waitMinutes(for centerID: UUID) async -> Int? {
        if let cached = waitMinutesCache[centerID] {
            return cached ?? nil
        }
        let stats = await DataManager.shared.effectiveWaitStats(careCenterID: centerID, force: false)
        let value: Int? = stats.averageMinutes > 0 ? stats.averageMinutes : nil
        waitMinutesCache[centerID] = value
        return value
    }

    private func updateWaitMinutesAndResort() async {
        // Fetch minutes for all centers concurrently
        await withTaskGroup(of: (UUID, Int?).self) { group in
            for center in careCenters {
                group.addTask { [centerID = center.id] in
                    let mins = await self.waitMinutes(for: centerID)
                    return (centerID, mins)
                }
            }
            var tmp: [UUID: Int?] = [:]
            for await (id, mins) in group {
                tmp[id] = mins
            }
            // Update cache
            self.waitMinutesCache.merge(tmp) { _, new in new }
        }

        // Rebuild ETA model to keep same set/order base then sort
        careCentersWithETA = careCenters.map { ($0, etaCache[$0.id]) }
        applyCurrentSort()

        await MainActor.run {
            self.tableView.reloadData()
        }
    }
    
    // MARK: - ETA
    
    private func requestETAIfNeeded(for center: CareCenter) {
        guard etaCache[center.id] == nil,
              !etaRequestsInFlight.contains(center.id),
              let origin = currentLocation?.coordinate else { return }
        
        etaRequestsInFlight.insert(center.id)
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        
        let directions = MKDirections(request: request)
        directions.calculateETA { [weak self] response, error in
            guard let self = self else { return }
            self.etaRequestsInFlight.remove(center.id)
            if let eta = response?.expectedTravelTime, eta > 0 {
                self.etaCache[center.id] = eta
                // Update model
                if let idx = self.careCentersWithETA.firstIndex(where: { $0.careCenter.id == center.id }) {
                    self.careCentersWithETA[idx].eta = eta
                }
                // Re-sort using current mode
                self.applyCurrentSort()
            }
        }
    }
    
    // MARK: - Header sizing refresh
    
    private func refreshHeaderSizeIfNeeded() {
        guard let header = tableView.tableHeaderView else { return }
        header.setNeedsLayout()
        header.layoutIfNeeded()
        let targetSize = CGSize(width: view.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let height = header.systemLayoutSizeFitting(targetSize).height
        if header.frame.height != height {
            var frame = header.frame
            frame.size.height = height
            header.frame = frame
            tableView.tableHeaderView = header
        }
    }
    
    // MARK: - Filter actions
    
    @objc private func didTapFilter() {
        // Build capability list
        let capabilities = DataManager.shared.getAllCapabilities()
        let alert = UIAlertController(title: "Filter by Capability", message: nil, preferredStyle: .actionSheet)
        
        // "All Care Centers" option to clear the filter
        alert.addAction(UIAlertAction(title: "All Care Centers", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            self.filterCapability = nil
            self.loadAllCareCenters()
        }))
        
        // Add an action per capability
        for cap in capabilities {
            alert.addAction(UIAlertAction(title: cap.name, style: .default, handler: { [weak self] _ in
                guard let self else { return }
                self.filterCapability = Capability(name: cap.name)
                self.loadFilteredCareCenters(by: self.filterCapability!)
            }))
        }
        
        // Cancel
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        // For iPad-style presentation if needed (action sheets require a source)
        if let pop = alert.popoverPresentationController {
            pop.sourceView = filterButton
            pop.sourceRect = filterButton.bounds
            pop.permittedArrowDirections = .up
        }
        
        present(alert, animated: true, completion: nil)
    }

    // MARK: - Sort actions

    @objc private func didTapSort() {
        let alert = UIAlertController(title: "Sort by", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Total Time (Wait + Travel)", style: .default, handler: { [weak self] _ in
            self?.currentSortMode = .total
        }))
        alert.addAction(UIAlertAction(title: "Travel Time", style: .default, handler: { [weak self] _ in
            self?.currentSortMode = .travel
        }))
        alert.addAction(UIAlertAction(title: "Wait Time", style: .default, handler: { [weak self] _ in
            self?.currentSortMode = .wait
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if let pop = alert.popoverPresentationController {
            pop.sourceView = sortButton
            pop.sourceRect = sortButton.bounds
            pop.permittedArrowDirections = .up
        }

        present(alert, animated: true, completion: nil)
    }

    private func updateSortButtonTitle() {
        switch currentSortMode {
        case .total:
            sortButton.setTitle(" Total", for: .normal)
        case .travel:
            sortButton.setTitle(" Travel", for: .normal)
        case .wait:
            sortButton.setTitle(" Wait", for: .normal)
        }
    }
    
    // MARK: - Actions
    
    private func showCareCenter(_ careCenter: CareCenter) {
        // If we are presented as a sheet, dismiss first, then present details from the presenter.
        if presentingViewController != nil {
            dismiss(animated: true) { [weak self] in
                self?.presentDetailsFromBestPresenter(careCenter)
            }
        } else {
            // Not presented modally; present directly.
            presentDetailsFromBestPresenter(careCenter)
        }
    }
    
    // Present details from the most reliable presenter available (self if visible, else our presenter, else top-most).
    private func presentDetailsFromBestPresenter(_ careCenter: CareCenter) {
        let presenter = self.presentingViewController ?? self.topMostPresenter()
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let detailsVC = storyboard.instantiateViewController(withIdentifier: "CareCenterDetails") as? CareCenterDetailsViewController else {
            assertionFailure("Failed to instantiate CareCenterDetailsViewController. Check storyboard ID and class.")
            return
        }
        detailsVC.careCenter = careCenter
        detailsVC.userCoordinate = currentLocation?.coordinate
        detailsVC.modalPresentationStyle = .pageSheet
        if let sheet = detailsVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            sheet.prefersGrabberVisible = true
        }
        presenter?.present(detailsVC, animated: true, completion: nil)
    }
    
    // Walk up to find the top-most presenter we can use if needed.
    private func topMostPresenter() -> UIViewController? {
        var root = view.window?.rootViewController ?? UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        while let presented = root?.presentedViewController {
            root = presented
        }
        return root ?? self
    }
}

// MARK: - UITableViewDataSource

extension CareCentersListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return careCentersWithETA.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: CareCenterTableViewCell.reuseIdentifier, for: indexPath) as? CareCenterTableViewCell else {
            return UITableViewCell()
        }
        
        let item = careCentersWithETA[indexPath.row]
        cell.configure(with: item.careCenter, distance: nil)
        // Use timing layout (right stack) and prefer "x hrs y min" format only in this controller
        cell.setDisplayStyle(.timing)
        cell.setPreferredTimeFormatLong(true)

        // Apply wait minutes if cached
        if let mins = (waitMinutesCache[item.careCenter.id] ?? nil) {
            cell.setWaitTime(minutes: mins)
        } else {
            // Cell may fetch stats itself; leave unset
        }
        
        // Apply ETA if cached; else request and clear stale
        if let eta = etaCache[item.careCenter.id] {
            cell.setTravelTime(seconds: Int(eta))
        } else {
            cell.setTravelTime(seconds: 0)
            requestETAIfNeeded(for: item.careCenter)
        }
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension CareCentersListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let careCenter = careCentersWithETA[indexPath.row].careCenter
        
        // Notify the landing page to zoom to this care center
        onCareCenterSelected?(careCenter)
        
        // Show care center details
        showCareCenter(careCenter)
    }
}

// MARK: - CLLocationManagerDelegate

extension CareCentersListViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        
        // With location available, request ETAs for all and sort by total time as they arrive
        requestETAsForAllIfPossible()
        // Ensure table shows current order
        tableView.reloadData()
        
        // Stop updating to save battery
        locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}

