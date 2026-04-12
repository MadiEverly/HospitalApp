import UIKit

final class FacilityIssueReportViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate, UITextFieldDelegate, UITextViewDelegate {

    private let categories = FacilityIssueCategory.allCases
    private let careCenterID: UUID

    private let picker = UIPickerView()
    private let detailsField = UITextField()
    private let notesView = UITextView()
    private let submitButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let stack = UIStackView()

    init(careCenterID: UUID) {
        self.careCenterID = careCenterID
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Report Facility Issue"

        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Category picker
        picker.dataSource = self
        picker.delegate = self
        picker.translatesAutoresizingMaskIntoConstraints = false

        let pickerLabel = UILabel()
        pickerLabel.text = "Category"
        pickerLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)

        // Details (short text)
        detailsField.borderStyle = .roundedRect
        detailsField.placeholder = "Details (e.g. Room 2, outpatient)"
        detailsField.delegate = self

        // Notes (optional longer)
        notesView.font = UIFont.systemFont(ofSize: 15)
        notesView.layer.borderWidth = 1
        notesView.layer.borderColor = UIColor.separator.cgColor
        notesView.layer.cornerRadius = 8
        notesView.isScrollEnabled = false
        notesView.text = ""
        notesView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)

        // Buttons
        var submitConfig = UIButton.Configuration.filled()
        submitConfig.title = "Submit"
        submitConfig.baseBackgroundColor = .systemBlue
        submitConfig.baseForegroundColor = .white
        submitButton.configuration = submitConfig
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)

        var cancelConfig = UIButton.Configuration.gray()
        cancelConfig.title = "Cancel"
        cancelButton.configuration = cancelConfig
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let buttonsRow = UIStackView(arrangedSubviews: [cancelButton, submitButton])
        buttonsRow.axis = .horizontal
        buttonsRow.spacing = 12
        buttonsRow.distribution = .fillEqually

        stack.addArrangedSubview(pickerLabel)
        stack.addArrangedSubview(picker)
        stack.addArrangedSubview(detailsField)

        let notesLabel = UILabel()
        notesLabel.text = "Notes (optional)"
        notesLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(notesLabel)
        stack.addArrangedSubview(notesView)
        stack.addArrangedSubview(buttonsRow)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    // MARK: Picker
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { categories.count }
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? { categories[row].displayName }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func submitTapped() {
        let category = categories[picker.selectedRow(inComponent: 0)]
        let detailsText = detailsField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = notesView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let combinedDetails: String?
        if let d = detailsText, !d.isEmpty {
            combinedDetails = notes.isEmpty ? d : "\(d) – \(notes)"
        } else {
            combinedDetails = notes.isEmpty ? nil : notes
        }

        Task {
            do {
                try await DataManager.shared.submitFacilityIssue(careCenterID: careCenterID, category: category, details: combinedDetails)
                dismiss(animated: true)
            } catch {
                let alert = UIAlertController(title: "Could not submit", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }
}
