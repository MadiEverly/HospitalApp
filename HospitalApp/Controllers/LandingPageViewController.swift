//
//  ViewController.swift
//  HospitalApp
//
//  Created by Duane Homick on 2026-01-28.
//

import UIKit
import MapKit
import CoreLocation

class LandingPageViewController: UIViewController, CLLocationManagerDelegate {

    private let presentCareCentersButton = UIButton(type: .system)
    private let searchTextField = UITextField()
    private let mapView = MKMapView()
    private let locationManager = CLLocationManager()
    private let recenterButton = UIButton(type: .system)
    private let capabilityScrollView = UIScrollView()
    private let capabilityStackView = UIStackView()
    private var isFollowingUser = true
    private var selectedCapability: Capability?
    private var careCentersObserver: NSObjectProtocol?
    
    // Search results
    private let searchResultsTableView = UITableView()
    private let searchResultsContainer = UIView()
    private var searchResults: [CareCenter] = []
    private var isSearchActive = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // Remove any navigation title text
        navigationItem.title = nil
        title = nil

        // Do any additional setup after loading the view.
        // From within a UIViewController (e.g., LandingPageViewController)
        
        setupMap()
        setupLocation()
        setupPresentCareCentersButton()
        setupRecenterButton()
        setupSearchTextField()
        setupSearchResults()
        setupCapabilityButtons()
        loadCareCenterAnnotations()
        
        // Add tap gesture to dismiss search when tapping on map
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMapTap))
        tapGesture.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tapGesture)

        careCentersObserver = NotificationCenter.default.addObserver(forName: Notification.Name.careCentersDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.loadCareCenterAnnotations()
            // Refresh capability buttons when care centers change (new capabilities may be added)
            self?.refreshCapabilityButtons()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Hide the navigation bar so the safe area top is directly under the status bar/Dynamic Island
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Restore for other screens
        navigationController?.setNavigationBarHidden(false, animated: false)
    }
    
    @objc private func handleMapTap() {
        // Dismiss keyboard if search field is active
        if searchTextField.isFirstResponder {
            searchTextField.resignFirstResponder()
            hideSearchResults(clearText: false) // Keep the text in case user wants to continue
        }
        
        // Hide search results if they're showing (but keyboard isn't active)
        else if isSearchActive {
            hideSearchResults(clearText: true) // Clear text when explicitly dismissing
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Removed automatic presentation of care centers sheet
    }

    @objc private func presentCareCentersFromButton() {
        presentCareCentersSheet()
    }
    
    private func presentCareCentersSheet() {
        // Avoid presenting multiple times if this VC reappears
        guard presentedViewController == nil else { return }

        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        // Updated to instantiate CareCentersListViewController
        guard let careCentersVC = storyboard.instantiateViewController(withIdentifier: "CareCenterList") as? CareCenterListViewController else {
            assertionFailure("Failed to instantiate CareCenterListViewController. Check storyboard ID and class.")
            return
        }

        // Set up callback for when a care center is selected
        careCentersVC.onCareCenterSelected = { [weak self] careCenter in
            self?.zoomToCareCenterPin(careCenter)
        }

        careCentersVC.modalPresentationStyle = .pageSheet

        if let sheet = careCentersVC.sheetPresentationController {
            // Quarter-height custom detent
            let quarterDetent = UISheetPresentationController.Detent.custom(identifier: .init("quarter")) { context in
                context.maximumDetentValue * 0.25
            }
            sheet.detents = [quarterDetent, .medium(), .large()]
            sheet.selectedDetentIdentifier = quarterDetent.identifier
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            sheet.prefersGrabberVisible = true
        }

        present(careCentersVC, animated: true)
    }
    
    private func setupPresentCareCentersButton() {
        // Configure floating button
        presentCareCentersButton.translatesAutoresizingMaskIntoConstraints = false
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        presentCareCentersButton.setImage(UIImage(systemName: "cross.case", withConfiguration: symbolConfig), for: .normal)
        presentCareCentersButton.tintColor = .black
        presentCareCentersButton.backgroundColor = .white
        presentCareCentersButton.layer.cornerRadius = 28
        presentCareCentersButton.layer.masksToBounds = true
        presentCareCentersButton.addTarget(self, action: #selector(presentCareCentersFromButton), for: .touchUpInside)
        view.addSubview(presentCareCentersButton)
        NSLayoutConstraint.activate([
            presentCareCentersButton.widthAnchor.constraint(equalToConstant: 56),
            presentCareCentersButton.heightAnchor.constraint(equalToConstant: 56),
            presentCareCentersButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            presentCareCentersButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }
    
    private func setupSearchTextField() {
        // Configure a Google Maps–style search field (visual only)
        searchTextField.translatesAutoresizingMaskIntoConstraints = false
        searchTextField.backgroundColor = UIColor.secondarySystemBackground
        searchTextField.textColor = .label
        searchTextField.font = UIFont.systemFont(ofSize: 16)
        searchTextField.placeholder = "Search"
        searchTextField.clearButtonMode = .whileEditing
        searchTextField.returnKeyType = .search
        searchTextField.borderStyle = .none
        searchTextField.layer.cornerRadius = 12
        searchTextField.layer.masksToBounds = true

        // Add a subtle shadow to lift it from the background
        searchTextField.layer.shadowColor = UIColor.black.cgColor
        searchTextField.layer.shadowOpacity = 0.08
        searchTextField.layer.shadowOffset = CGSize(width: 0, height: 2)
        searchTextField.layer.shadowRadius = 6

        // Left view with magnifying glass icon
        let magnifier = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        magnifier.tintColor = .secondaryLabel
        magnifier.contentMode = .scaleAspectFit
        let leftContainer = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        magnifier.frame = CGRect(x: 12, y: 8, width: 20, height: 20)
        leftContainer.addSubview(magnifier)
        searchTextField.leftView = leftContainer
        searchTextField.leftViewMode = .always

        // Set delegates for search functionality
        searchTextField.delegate = self
        searchTextField.addTarget(self, action: #selector(searchTextDidChange), for: .editingChanged)

        // Add to view hierarchy
        view.addSubview(searchTextField)

        // Layout constraints: positioned next to recenter button
        NSLayoutConstraint.activate([
            searchTextField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0),
            searchTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchTextField.trailingAnchor.constraint(equalTo: recenterButton.leadingAnchor, constant: -8),
            searchTextField.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Ensure the floating buttons stay above the field visually
        view.bringSubviewToFront(recenterButton)
        view.bringSubviewToFront(presentCareCentersButton)
    }
    
    private func setupSearchResults() {
        // Configure container for search results
        searchResultsContainer.translatesAutoresizingMaskIntoConstraints = false
        searchResultsContainer.backgroundColor = .systemBackground
        searchResultsContainer.layer.cornerRadius = 12
        searchResultsContainer.layer.masksToBounds = true
        searchResultsContainer.layer.shadowColor = UIColor.black.cgColor
        searchResultsContainer.layer.shadowOpacity = 0.15
        searchResultsContainer.layer.shadowOffset = CGSize(width: 0, height: 4)
        searchResultsContainer.layer.shadowRadius = 8
        searchResultsContainer.isHidden = true
        view.addSubview(searchResultsContainer)
        
        // Configure table view for search results
        searchResultsTableView.translatesAutoresizingMaskIntoConstraints = false
        searchResultsTableView.delegate = self
        searchResultsTableView.dataSource = self
        searchResultsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "SearchResultCell")
        searchResultsTableView.layer.cornerRadius = 12
        searchResultsTableView.backgroundColor = .systemBackground
        searchResultsTableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        searchResultsTableView.rowHeight = UITableView.automaticDimension
        searchResultsTableView.estimatedRowHeight = 60
        searchResultsContainer.addSubview(searchResultsTableView)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            searchResultsContainer.topAnchor.constraint(equalTo: searchTextField.bottomAnchor, constant: 8),
            searchResultsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchResultsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchResultsContainer.heightAnchor.constraint(equalToConstant: 300),
            
            searchResultsTableView.topAnchor.constraint(equalTo: searchResultsContainer.topAnchor),
            searchResultsTableView.leadingAnchor.constraint(equalTo: searchResultsContainer.leadingAnchor),
            searchResultsTableView.trailingAnchor.constraint(equalTo: searchResultsContainer.trailingAnchor),
            searchResultsTableView.bottomAnchor.constraint(equalTo: searchResultsContainer.bottomAnchor)
        ])
        
        // Ensure search results appear above other elements
        view.bringSubviewToFront(searchResultsContainer)
    }
    
    @objc private func searchTextDidChange() {
        guard let searchText = searchTextField.text, !searchText.isEmpty else {
            hideSearchResults(clearText: false) // Don't clear text - it's already being cleared by user
            return
        }
        
        performSearch(with: searchText)
    }
    
    private func performSearch(with query: String) {
        let allCareCenters = DataManager.shared.readAll()
        let lowercasedQuery = query.lowercased()
        
        // Search by name, address components, and capabilities
        searchResults = allCareCenters.filter { careCenter in
            // Check name
            if careCenter.name.lowercased().contains(lowercasedQuery) {
                return true
            }
            
            // Check address components
            if careCenter.streetAddress.lowercased().contains(lowercasedQuery) {
                return true
            }
            
            if careCenter.city.lowercased().contains(lowercasedQuery) {
                return true
            }
            
            if careCenter.region.lowercased().contains(lowercasedQuery) {
                return true
            }
            
            // Check capabilities
            for capability in careCenter.capabilities {
                if capability.name.lowercased().contains(lowercasedQuery) {
                    return true
                }
            }
            
            return false
        }
        
        // Show search results
        isSearchActive = true
        searchResultsTableView.reloadData()
        showSearchResults()
    }
    
    private func showSearchResults() {
        searchResultsContainer.isHidden = false
        capabilityScrollView.isHidden = true
        
        // Bring to front to ensure visibility
        view.bringSubviewToFront(searchResultsContainer)
    }
    
    private func hideSearchResults(clearText: Bool = true) {
        isSearchActive = false
        searchResultsContainer.isHidden = true
        capabilityScrollView.isHidden = false
        searchResults.removeAll()
        searchResultsTableView.reloadData()
        
        if clearText {
            searchTextField.text = ""
        }
    }

    private func setupMap() {
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.delegate = self
        view.addSubview(mapView)
        view.sendSubviewToBack(mapView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupLocation() {
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
            mapView.showsUserLocation = true
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    private func setupRecenterButton() {
        recenterButton.translatesAutoresizingMaskIntoConstraints = false
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        recenterButton.setImage(UIImage(systemName: "location", withConfiguration: symbolConfig), for: .normal)
        recenterButton.tintColor = .black
        recenterButton.backgroundColor = .white
        recenterButton.layer.cornerRadius = 22
        recenterButton.layer.masksToBounds = true
        
        // Add shadow matching search field
        recenterButton.layer.shadowColor = UIColor.black.cgColor
        recenterButton.layer.shadowOpacity = 0.08
        recenterButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        recenterButton.layer.shadowRadius = 6
        
        recenterButton.addTarget(self, action: #selector(recenterMapToUser), for: .touchUpInside)
        view.addSubview(recenterButton)
        NSLayoutConstraint.activate([
            recenterButton.widthAnchor.constraint(equalToConstant: 44),
            recenterButton.heightAnchor.constraint(equalToConstant: 44),
            recenterButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            recenterButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0)
        ])
        view.bringSubviewToFront(recenterButton)
    }
    
    private func setupCapabilityButtons() {
        // Configure scroll view
        capabilityScrollView.translatesAutoresizingMaskIntoConstraints = false
        capabilityScrollView.showsHorizontalScrollIndicator = false
        capabilityScrollView.showsVerticalScrollIndicator = false
        capabilityScrollView.backgroundColor = .clear
        view.addSubview(capabilityScrollView)
        
        // Configure stack view
        capabilityStackView.translatesAutoresizingMaskIntoConstraints = false
        capabilityStackView.axis = .horizontal
        capabilityStackView.spacing = 8
        capabilityStackView.alignment = .center
        capabilityScrollView.addSubview(capabilityStackView)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            capabilityScrollView.topAnchor.constraint(equalTo: searchTextField.bottomAnchor, constant: 4),
            capabilityScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            capabilityScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            capabilityScrollView.heightAnchor.constraint(equalToConstant: 36),
            
            capabilityStackView.topAnchor.constraint(equalTo: capabilityScrollView.topAnchor),
            capabilityStackView.leadingAnchor.constraint(equalTo: capabilityScrollView.leadingAnchor),
            capabilityStackView.trailingAnchor.constraint(equalTo: capabilityScrollView.trailingAnchor),
            capabilityStackView.bottomAnchor.constraint(equalTo: capabilityScrollView.bottomAnchor),
            capabilityStackView.heightAnchor.constraint(equalTo: capabilityScrollView.heightAnchor)
        ])
        
        // Load capabilities and create buttons
        refreshCapabilityButtons()
        
        // Bring to front to ensure visibility above map
        view.bringSubviewToFront(capabilityScrollView)
        view.bringSubviewToFront(recenterButton)
        view.bringSubviewToFront(presentCareCentersButton)
    }
    
    private func refreshCapabilityButtons() {
        // Remove existing buttons
        capabilityStackView.arrangedSubviews.forEach { view in
            capabilityStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        // Get all capabilities and create buttons (already deduped by name in DataManager)
        let capabilities = DataManager.shared.getAllCapabilities()
        
        guard !capabilities.isEmpty else {
            print("No capabilities found to display")
            return
        }
        
        for capability in capabilities {
            let button = createCapabilityButton(for: capability)
            capabilityStackView.addArrangedSubview(button)
        }
        
        print("Loaded \(capabilities.count) capability buttons")
    }
    
    private func createCapabilityButton(for capability: Capability) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(capability.name, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        button.setTitleColor(.label, for: .normal)
        button.backgroundColor = UIColor.secondarySystemBackground
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        button.layer.cornerRadius = 18
        
        // Don't set masksToBounds to true if you want shadows to show
        // Instead, handle clipping separately if needed
        button.clipsToBounds = false
        
        // Add shadow
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.08
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        
        // Use title for identification; avoid relying on UUIDs that may differ across centers
        button.addTarget(self, action: #selector(capabilityButtonTapped(_:)), for: .touchUpInside)
        
        return button
    }
    
    @objc private func capabilityButtonTapped(_ sender: UIButton) {
        // Use the button title (capability name) instead of UUID to avoid duplicates created server-side
        guard let name = sender.title(for: .normal), !name.isEmpty else {
            return
        }
        // Create a transient Capability with this name; filtering will be name-based
        selectedCapability = Capability(name: name)
        presentCareCentersSheetWithFilter()
    }
    
    private func presentCareCentersSheetWithFilter() {
        // Avoid presenting multiple times if this VC reappears
        guard presentedViewController == nil else { return }

        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        // Updated to instantiate CareCentersListViewController
        guard let careCentersVC = storyboard.instantiateViewController(withIdentifier: "CareCenterList") as? CareCenterListViewController else {
            assertionFailure("Failed to instantiate CareCenterListViewController. Check storyboard ID and class.")
            return
        }

        // Pass the selected capability to the care centers view controller
        careCentersVC.filterCapability = selectedCapability
        
        // Set up callback for when a care center is selected
        careCentersVC.onCareCenterSelected = { [weak self] careCenter in
            self?.zoomToCareCenterPin(careCenter)
        }
        
        careCentersVC.modalPresentationStyle = .pageSheet

        if let sheet = careCentersVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            sheet.prefersGrabberVisible = true
        }

        present(careCentersVC, animated: true)
    }



    @objc private func recenterMapToUser() {
        isFollowingUser = true
        if let location = locationManager.location?.coordinate {
            // Find the nearest care center to include in the visible region
            let userLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
            let careCenters = DataManager.shared.readAll()
            
            // Calculate distances and find the nearest care center
            let sortedCareCenters = careCenters.sorted { center1, center2 in
                let location1 = CLLocation(latitude: center1.latitude, longitude: center1.longitude)
                let location2 = CLLocation(latitude: center2.latitude, longitude: center2.longitude)
                return userLocation.distance(from: location1) < userLocation.distance(from: location2)
            }
            
            if let nearestCenter = sortedCareCenters.first {
                // Create a region that includes both the user and the nearest care center
                let centerCoordinate = CLLocation(latitude: nearestCenter.latitude, longitude: nearestCenter.longitude)
                
                // Calculate the region that includes both points with some padding
                let latDelta = abs(location.latitude - nearestCenter.latitude) * 2.5
                let lonDelta = abs(location.longitude - nearestCenter.longitude) * 2.5
                
                // Use minimum span to ensure a reasonable zoom level
                let minSpan = 0.02
                let spanLatitude = max(latDelta, minSpan)
                let spanLongitude = max(lonDelta, minSpan)
                
                // Calculate the center point between user and nearest care center
                let centerLat = (location.latitude + nearestCenter.latitude) / 2
                let centerLon = (location.longitude + nearestCenter.longitude) / 2
                let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
                
                let span = MKCoordinateSpan(latitudeDelta: spanLatitude, longitudeDelta: spanLongitude)
                let region = MKCoordinateRegion(center: center, span: span)
                mapView.setRegion(region, animated: true)
            } else {
                // Fallback: just center on user if no care centers found
                let region = MKCoordinateRegion(center: location, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
                mapView.setRegion(region, animated: true)
            }
        }
    }
    
    // MARK: - Care Center Annotations
    
    private func loadCareCenterAnnotations() {
        // Remove existing annotations (except user location)
        let existingAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(existingAnnotations)
        
        // Get all care centers
        let careCenters = DataManager.shared.readAll()
        
        // Create annotations for each care center
        let annotations = careCenters.map { CareCenterAnnotation(careCenter: $0) }
        
        // Add to map
        mapView.addAnnotations(annotations)
        
        // Optionally, adjust map region to show all care centers
        if !annotations.isEmpty {
            fitMapToShowAnnotations()
        }
    }
    
    private func zoomToCareCenterPin(_ careCenter: CareCenter) {
        // Disable user following mode
        isFollowingUser = false
        
        let coordinate = CLLocationCoordinate2D(latitude: careCenter.latitude, longitude: careCenter.longitude)
        
        // Calculate the span for zoom level
        let span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        
        // Offset the center point DOWN so the pin appears in the TOP 25% of the screen
        // The bottom sheet covers 25-75% of the screen depending on detent
        // By shifting the center down, the pin appears in the upper visible area
        let latitudeOffset = span.latitudeDelta * 0.25 // Shift center down by 25% of span
        let adjustedCenter = CLLocationCoordinate2D(
            latitude: coordinate.latitude - latitudeOffset, // Subtract to move center south, pin appears north
            longitude: coordinate.longitude
        )
        
        let region = MKCoordinateRegion(center: adjustedCenter, span: span)
        mapView.setRegion(region, animated: true)
        
        // Optionally, select the annotation briefly to highlight it
        if let annotation = mapView.annotations.first(where: {
            guard let careCenterAnnotation = $0 as? CareCenterAnnotation else { return false }
            return careCenterAnnotation.careCenter.id == careCenter.id
        }) {
            // Briefly select and deselect to provide visual feedback
            mapView.selectAnnotation(annotation, animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.mapView.deselectAnnotation(annotation, animated: true)
            }
        }
    }
    
    private func fitMapToShowAnnotations() {
        // Get all care center annotations
        let careCenterAnnotations = mapView.annotations.filter { $0 is CareCenterAnnotation }
        
        guard !careCenterAnnotations.isEmpty else { return }
        
        // Calculate bounding box
        var minLat = careCenterAnnotations[0].coordinate.latitude
        var maxLat = careCenterAnnotations[0].coordinate.latitude
        var minLon = careCenterAnnotations[0].coordinate.longitude
        var maxLon = careCenterAnnotations[0].coordinate.longitude
        
        for annotation in careCenterAnnotations {
            minLat = min(minLat, annotation.coordinate.latitude)
            maxLat = max(maxLat, annotation.coordinate.latitude)
            minLon = min(minLon, annotation.coordinate.longitude)
            maxLon = max(maxLon, annotation.coordinate.longitude)
        }
        
        // Create region with some padding
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.3,
            longitudeDelta: (maxLon - minLon) * 1.3
        )
        
        let region = MKCoordinateRegion(center: center, span: span)
        mapView.setRegion(region, animated: true)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            mapView.showsUserLocation = true
            manager.startUpdatingLocation()
        case .denied, .restricted:
            break
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isFollowingUser, let location = locations.last?.coordinate else { return }
        
        // Find the nearest care center to include in the visible region
        let userLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let careCenters = DataManager.shared.readAll()
        
        // Calculate distances and find the nearest care center
        let sortedCareCenters = careCenters.sorted { center1, center2 in
            let location1 = CLLocation(latitude: center1.latitude, longitude: center1.longitude)
            let location2 = CLLocation(latitude: center2.latitude, longitude: center2.longitude)
            return userLocation.distance(from: location1) < userLocation.distance(from: location2)
        }
        
        if let nearestCenter = sortedCareCenters.first {
            // Create a region that includes both the user and the nearest care center
            let centerCoordinate = CLLocation(latitude: nearestCenter.latitude, longitude: nearestCenter.longitude)
            
            // Calculate the region that includes both points with some padding
            let latDelta = abs(location.latitude - nearestCenter.latitude) * 2.5
            let lonDelta = abs(location.longitude - nearestCenter.longitude) * 2.5
            
            // Use minimum span to ensure a reasonable zoom level
            let minSpan = 0.02
            let spanLatitude = max(latDelta, minSpan)
            let spanLongitude = max(lonDelta, minSpan)
            
            // Calculate the center point between user and nearest care center
            let centerLat = (location.latitude + nearestCenter.latitude) / 2
            let centerLon = (location.longitude + nearestCenter.longitude) / 2
            let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
            
            let span = MKCoordinateSpan(latitudeDelta: spanLatitude, longitudeDelta: spanLongitude)
            let region = MKCoordinateRegion(center: center, span: span)
            mapView.setRegion(region, animated: true)
        } else {
            // Fallback: just center on user if no care centers found
            let region = MKCoordinateRegion(center: location, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
            mapView.setRegion(region, animated: true)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Handle location errors if needed
    }
    
    deinit {
        if let token = careCentersObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

// MARK: - UITextFieldDelegate

extension LandingPageViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // Dismiss keyboard when return is tapped
        textField.resignFirstResponder()
        
        // If we have search results, select the first one
        if !searchResults.isEmpty {
            let firstResult = searchResults[0]
            hideSearchResults(clearText: true) // Clear text after selecting
            zoomToCareCenterPin(firstResult)
            showCareCenterDetails(firstResult)
        }
        
        return true
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        // Show search results if there's existing text
        if let text = textField.text, !text.isEmpty {
            performSearch(with: text)
        }
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        // Don't auto-hide search results - let user explicitly dismiss by tapping map or selecting a result
        // This prevents the results from disappearing when interacting with the table view
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate (Search Results)

extension LandingPageViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if searchResults.isEmpty && isSearchActive {
            return 1 // Show "No results" cell
        }
        return searchResults.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Create cell with subtitle style for showing address
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "SearchResultCell")
        
        // Configure cell to show subtitle
        cell.textLabel?.numberOfLines = 1
        cell.detailTextLabel?.numberOfLines = 2
        
        // Show "No results" if search is empty
        if searchResults.isEmpty && isSearchActive {
            cell.textLabel?.text = "No results found"
            cell.textLabel?.textColor = .secondaryLabel
            cell.textLabel?.font = UIFont.systemFont(ofSize: 16)
            cell.detailTextLabel?.text = nil
            cell.selectionStyle = .none
            cell.accessoryType = .none
            return cell
        }
        
        let careCenter = searchResults[indexPath.row]
        
        // Configure cell with care center info
        cell.textLabel?.text = careCenter.name
        cell.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        cell.textLabel?.textColor = .label
        
        cell.detailTextLabel?.text = careCenter.fullAddress
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 14)
        cell.detailTextLabel?.textColor = .secondaryLabel
        
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard !searchResults.isEmpty else { return }
        
        let selectedCareCenter = searchResults[indexPath.row]
        
        // Clear search and hide results
        searchTextField.resignFirstResponder()
        hideSearchResults(clearText: true) // Clear text after selecting a result
        
        // Zoom to the selected care center
        zoomToCareCenterPin(selectedCareCenter)
        
        // Show details
        showCareCenterDetails(selectedCareCenter)
    }
}

extension LandingPageViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        // Detect if the change is due to a user gesture. On iOS 13+, the view has a private gesture recognizer; we can infer via any touches in view.
        if let view = mapView.subviews.first, let gestureRecognizers = view.gestureRecognizers {
            if gestureRecognizers.contains(where: { $0.state == .began || $0.state == .changed }) {
                isFollowingUser = false
            }
        }
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // Don't customize user location annotation
        if annotation is MKUserLocation {
            return nil
        }
        
        // Handle care center annotations
        if let careCenterAnnotation = annotation as? CareCenterAnnotation {
            let identifier = "CareCenterAnnotation"
            
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            
            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = false // Disable callout since we're showing details immediately
            } else {
                annotationView?.annotation = annotation
            }
            
            // Customize appearance
            annotationView?.markerTintColor = .systemRed
            annotationView?.glyphImage = UIImage(systemName: "cross.case.fill")
            
            return annotationView
        }
        
        return nil
    }
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        // Immediately present details when annotation is tapped
        if let careCenterAnnotation = view.annotation as? CareCenterAnnotation {
            // Zoom to the pin first
            zoomToCareCenterPin(careCenterAnnotation.careCenter)
            
            // Then show details
            showCareCenterDetails(careCenterAnnotation.careCenter)
            
            // Deselect the annotation after a brief moment
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                mapView.deselectAnnotation(careCenterAnnotation, animated: false)
            }
        }
    }
    
    private func showCareCenterDetails(_ careCenter: CareCenter) {
        // If we already have something presented (like the list), dismiss it first
        if presentedViewController != nil {
            dismiss(animated: true) { [weak self] in
                self?.presentCareCenterDetails(careCenter)
            }
        } else {
            presentCareCenterDetails(careCenter)
        }
    }
    
    private func presentCareCenterDetails(_ careCenter: CareCenter) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let detailsVC = storyboard.instantiateViewController(withIdentifier: "CareCenterDetails") as? CareCenterDetailsViewController else {
            assertionFailure("Failed to instantiate CareCenterDetailsViewController.")
            return
        }
        
        // Pass the care center to the details view controller
        detailsVC.careCenter = careCenter
        
        detailsVC.modalPresentationStyle = .pageSheet
        if let sheet = detailsVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            sheet.prefersGrabberVisible = true
        }
        
        present(detailsVC, animated: true)
    }
}

