//
//  ViewController.swift
//  HospitalApp
//
//  Created by Duane Homick on 2026-01-28.
//

import UIKit

class CareCenterDetailsViewController: UIViewController {

    // MARK: - Properties
    var careCenter: CareCenter?
    
    private let closeButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        self.view.layer.backgroundColor = UIColor.white.cgColor
        setupTableView()
        setupCloseButton()
    }
    
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(CareCenterDetailHeaderCell.self, forCellReuseIdentifier: CareCenterDetailHeaderCell.reuseIdentifier)
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
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
        closeButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12)
        ])
    }

    @objc private func dismissSelf() {
        dismiss(animated: true, completion: nil)
    }

}

// MARK: - UITableViewDataSource
extension CareCenterDetailsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return careCenter != nil ? 1 : 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: CareCenterDetailHeaderCell.reuseIdentifier, for: indexPath) as? CareCenterDetailHeaderCell,
              let careCenter = careCenter else {
            return UITableViewCell()
        }
        
        cell.configure(with: careCenter)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension CareCenterDetailsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 300
    }
}
