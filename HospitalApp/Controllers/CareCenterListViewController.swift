//  ViewController.swift
//  HospitalApp
//
//  Created by Duane Homick on 2026-01-28.
//

import UIKit
import CoreLocation
import MapKit

extension Notification.Name {
    static let careCentersDidChange = Notification.Name("careCentersDidChange")
}

class CareCenterListViewController: UIViewController {

    // MARK: - Properties
    var filterCapability: Capability?
    var onCareCenterSelected: ((CareCenter) -> Void)?
    private var careCenters: [CareCenter] = []
    // Keep parallel model that carries ETA for sorting
    private var careCentersWithETA: [(careCenter: CareCenter, eta: TimeInterval?)] = []
    private let tableView = UITableView()
    private let headerView = UIView()
    private let headerLabel = UILabel()
    private var careCentersObserver: NSObjectProtocol?

    // ETA support
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var etaCache: [UUID: TimeInterval] = [:]
    private var etaRequestsInFlight: Set<UUID> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        
        setupHeaderView()
        setupTableView()
        setupLocationManager()
        
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
            // Clear ETAs on dataset change
            self.etaCache.removeAll()
            self.etaRequestsInFlight.removeAll()
            self.rebuildETAModelAndResort()
            self.tableView.reloadData()
            self.requestETAsForAllIfPossible()
        }
    }
    
    deinit {
        if let obs = careCentersObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
    
    // MARK: - Setup
    
    private func setupHeaderView() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = .systemBackground
        view.addSubview(headerView)
        
        // Configure header label
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.text = filterCapability?.name ?? "All Care Centers"
        headerLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        headerLabel.textColor = .label
        headerLabel.numberOfLines = 1
        headerView.addSubview(headerLabel)
        
        // Add a separator line at the bottom
        let separatorLine = UIView()
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        separatorLine.backgroundColor = .separator
        headerView.addSubview(separatorLine)
        
        NSLayoutConstraint.activate([
            // Header view at top
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 60),
            
            // Header label
            headerLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            headerLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            headerLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            // Separator line
            separatorLine.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            separatorLine.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 0.5)
        ])
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
        
        // Always place table view below header
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest

        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }

        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }
    
    // MARK: - Data Loading
    
    private func loadAllCareCenters() {
        careCenters = DataManager.shared.readAll()
        rebuildETAModelAndResort()
        tableView.reloadData()
        requestETAsForAllIfPossible()
        print("Loaded \(careCenters.count) care centers")
    }
    
    private func loadFilteredCareCenters(by capability: Capability) {
        careCenters = DataManager.shared.filter(byCapability: capability)
        rebuildETAModelAndResort()
        tableView.reloadData()
        requestETAsForAllIfPossible()
        print("Filtered by \(capability.name): \(careCenters.count) care centers")
    }
    
    private func rebuildETAModelAndResort() {
        careCentersWithETA = careCenters.map { ($0, etaCache[$0.id]) }
        sortByETAAscending()
    }
    
    private func sortByETAAscending() {
        // Sort: non-nil ETA ascending first; nil ETAs sink; stable among nils using original order
        careCentersWithETA.sort { lhs, rhs in
            switch (lhs.eta, rhs.eta) {
            case let (l?, r?):
                if l != r { return l < r }
                // tie-breaker by name for deterministic order
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
    
    // MARK: - ETA
    private func requestETAsForAllIfPossible() {
        guard currentLocation != nil else { return }
        for item in careCentersWithETA {
            requestETAIfNeeded(for: item.careCenter)
        }
    }

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
        directions.calculateETA { [weak self] response, _ in
            guard let self = self else { return }
            self.etaRequestsInFlight.remove(center.id)
            if let eta = response?.expectedTravelTime, eta > 0 {
                self.etaCache[center.id] = eta
                // Update model entry
                if let idx = self.careCentersWithETA.firstIndex(where: { $0.careCenter.id == center.id }) {
                    self.careCentersWithETA[idx].eta = eta
                }
                // Resort by ETA and reload
                self.sortByETAAscending()
                self.tableView.reloadData()
            }
        }
    }
    
    // MARK: - Actions
    
    private func showCareCenter(_ careCenter: CareCenter) {
        // Dismiss this sheet first, then let the presenting view controller handle the details
        dismiss(animated: true) { [weak self] in
            self?.presentDetailsFromParent(careCenter)
        }
    }
    
    private func presentDetailsFromParent(_ careCenter: CareCenter) {
        // Get the presenting view controller (should be LandingPageViewController)
        guard let landingVC = presentingViewController as? LandingPageViewController else {
            return
        }
        
        // Instantiate CareCenterDetailsViewController from storyboard
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let detailsVC = storyboard.instantiateViewController(withIdentifier: "CareCenterDetails") as? CareCenterDetailsViewController else {
            assertionFailure("Failed to instantiate CareCenterDetailsViewController. Check storyboard ID and class.")
            return
        }
        
        // Set the care center data
        detailsVC.careCenter = careCenter
        // No need to pass userCoordinate here; details VC can compute ETA if needed
        
        // Present as a page sheet at medium height
        detailsVC.modalPresentationStyle = .pageSheet
        if let sheet = detailsVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            sheet.prefersGrabberVisible = true
        }
        
        landingVC.present(detailsVC, animated: true, completion: nil)
    }
}

// MARK: - UITableViewDataSource

extension CareCenterListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return careCentersWithETA.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        guard let cell = tableView.dequeueReusableCell(withIdentifier: CareCenterTableViewCell.reuseIdentifier, for: indexPath) as? CareCenterTableViewCell else {
            return UITableViewCell()
        }
        
        let item = careCentersWithETA[indexPath.row]
        let center = item.careCenter
        cell.configure(with: center, distance: nil)
        cell.setDisplayStyle(.directionsButton)

        // Use a route-style SF Symbol for the travel (directions) pill in this controller
        cell.setTravelPillIcon(systemName: "arrow.triangle.turn.up.right.diamond.fill")

        // Apply travel ETA if cached
        if let eta = etaCache[center.id] {
            cell.setTravelTime(seconds: Int(eta))
        } else {
            // Trigger request; pill will show "No ETA" until filled
            requestETAIfNeeded(for: center)
        }
        
        // Wait pill will update from DataManager notifications automatically; nothing else needed here
        return cell
    }
}

// MARK: - UITableViewDelegate

extension CareCenterListViewController: UITableViewDelegate {
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

extension CareCenterListViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        requestETAsForAllIfPossible()
        // Resort if any ETAs already present
        sortByETAAscending()
        tableView.reloadData()
        manager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Handle location errors if needed
        print("Location error (singular list): \(error.localizedDescription)")
    }
}

