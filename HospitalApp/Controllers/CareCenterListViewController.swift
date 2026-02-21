//  ViewController.swift
//  HospitalApp
//
//  Created by Duane Homick on 2026-01-28.
//

import UIKit
import CoreLocation

extension Notification.Name {
    static let careCentersDidChange = Notification.Name("careCentersDidChange")
}

class CareCenterListViewController: UIViewController {

    // MARK: - Properties
    var filterCapability: Capability?
    var onCareCenterSelected: ((CareCenter) -> Void)?
    private var careCenters: [CareCenter] = []
    private var careCentersWithDistance: [(careCenter: CareCenter, distance: Double?)] = []
    private let tableView = UITableView()
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private let headerView = UIView()
    private let headerLabel = UILabel()
    private var careCentersObserver: NSObjectProtocol?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        self.view.backgroundColor = .systemBackground
        
        setupLocationManager()
        setupHeaderView()
        setupTableView()
        
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
    
    private func setupHeaderView() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = .systemBackground
        view.addSubview(headerView)
        
        // Configure header label
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        // Show capability name if filtering, otherwise show "All Care Centers"
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
    
    // MARK: - Data Loading
    
    private func loadAllCareCenters() {
        careCenters = DataManager.shared.readAll()
        sortCareCentersByDistance()
        tableView.reloadData()
        print("Loaded \(careCenters.count) care centers")
    }
    
    private func loadFilteredCareCenters(by capability: Capability) {
        careCenters = DataManager.shared.filter(byCapability: capability)
        sortCareCentersByDistance()
        tableView.reloadData()
        print("Filtered by \(capability.name): \(careCenters.count) care centers")
    }
    
    private func sortCareCentersByDistance() {
        guard let userLocation = currentLocation else {
            // No location available, just show care centers without distance sorting
            careCentersWithDistance = careCenters.map { ($0, nil) }
            return
        }
        
        // Calculate distances and sort
        careCentersWithDistance = careCenters.map { careCenter in
            let careCenterLocation = CLLocation(latitude: careCenter.latitude, longitude: careCenter.longitude)
            let distance = userLocation.distance(from: careCenterLocation)
            return (careCenter, distance)
        }
        
        // Sort by distance (ascending)
        careCentersWithDistance.sort { lhs, rhs in
            guard let lhsDistance = lhs.distance, let rhsDistance = rhs.distance else {
                return false
            }
            return lhsDistance < rhsDistance
        }
    }
    
    // MARK: - Actions
    
    private func showCareCenter(_ careCenter: CareCenter) {
        // Dismiss this sheet first, then let the presenting view controller handle the details
        dismiss(animated: true) { [weak self] in
            // Notify the landing page that a care center was selected
            // The landing page will handle presenting the details
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
        return careCentersWithDistance.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: CareCenterTableViewCell.reuseIdentifier, for: indexPath) as? CareCenterTableViewCell else {
            return UITableViewCell()
        }
        
        let item = careCentersWithDistance[indexPath.row]
        cell.configure(with: item.careCenter, distance: item.distance)
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension CareCenterListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let careCenter = careCentersWithDistance[indexPath.row].careCenter
        
        // Notify the landing page to zoom to this care center
        onCareCenterSelected?(careCenter)
        
        // Show care center details
        showCareCenter(careCenter)
    }
}

// MARK: - CLLocationManagerDelegate

extension CareCenterListViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        
        // Re-sort and reload when we get location
        sortCareCentersByDistance()
        tableView.reloadData()
        
        // Stop updating to save battery
        locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}
