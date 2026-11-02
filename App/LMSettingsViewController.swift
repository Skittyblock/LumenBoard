import UIKit

enum LMSettingsSection: Int {
    case iconStyle = 0
    case iconCache
    case troubleshooting
    case about
    case count
}

final class LMSettingsViewController: UITableViewController {
    private var settingsSnapshot = LMConfigStore.SettingsSnapshot()

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = LMLocalized("Settings")
        navigationItem.largeTitleDisplayMode = .never
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)

        Task { [weak self] in
            let settings = await LMConfigStore.shared.settingsSnapshot()
            guard let self else { return }
            settingsSnapshot = settings
            tableView.reloadData()
        }
    }

    func switchWithValue(_ value: Bool, action: Selector) -> UISwitch {
        let toggle = UISwitch()
        toggle.isOn = value
        toggle.addTarget(self, action: action, for: .valueChanged)
        return toggle
    }

    func save() async {
        do {
            try await LMConfigStore.shared.save()
        } catch {
            let alert = UIAlertController(title: LMLocalized("Couldn't save"), message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: LMLocalized("OK"), style: .cancel))
            present(alert, animated: true)
        }
    }

    @objc
    func systemShapeChanged(_ toggle: UISwitch) {
        settingsSnapshot.useSystemIconShape = toggle.isOn
        Task {
            await LMConfigStore.shared.setUseSystemIconShape(toggle.isOn)
            await save()
        }
    }

    @objc
    func keepAppearanceChanged(_ toggle: UISwitch) {
        settingsSnapshot.keepIconsInDarkAndTinted = toggle.isOn
        Task {
            await LMConfigStore.shared.setKeepIconsInDarkAndTinted(toggle.isOn)
            await save()
        }
    }

    func confirmClearIconCache() {
        let alert = UIAlertController(
            title: LMLocalized("Clear icon cache?"),
            message: LMLocalized("All app icons are rendered again, then SpringBoard restarts. This can take a minute."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: LMLocalized("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: LMLocalized("Clear & Respring"), style: .destructive) { _ in
            Task {
                await self.save()
                let applyVC = LMApplyViewController(clearingIconCache: true)!
                self.present(applyVC, animated: true)
            }
        })
        present(alert, animated: true)
    }
}

// MARK: Table view
extension LMSettingsViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return LMSettingsSection.count.rawValue
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch LMSettingsSection(rawValue: section) {
            case .iconStyle: return 2
            case .iconCache: return 1
            case .troubleshooting: return 1
            case .about: return 2
            default: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch LMSettingsSection(rawValue: section) {
            case .iconStyle: return LMLocalized("Theme icons")
            case .iconCache: return LMLocalized("Icon cache")
            case .troubleshooting: return LMLocalized("Troubleshooting")
            case .about: return LMLocalized("About")
            default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch LMSettingsSection(rawValue: section) {
            case .iconStyle: return LMLocalized("Theme icons keep their own shape unless \"iOS icon shape\" is on. Tap Apply afterwards.")
            case .iconCache: return LMLocalized("Renders every app icon again. Use it if icons still look wrong after installing or updating themes.")
            case .troubleshooting: return LMLocalized("Shows what LumenBoard did in SpringBoard and iconservicesagent. Copy the report if your icons don't change.")
            default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        cell.selectionStyle = .none

        switch LMSettingsSection(rawValue: indexPath.section) {
            case .iconStyle:
                if indexPath.row == 0 {
                    content.text = LMLocalized("iOS icon shape")
                    content.image = UIImage(systemName: "app")
                    cell.accessoryView = switchWithValue(settingsSnapshot.useSystemIconShape, action: #selector(systemShapeChanged(_:)))
                } else {
                    content.text = LMLocalized("Keep in dark & tinted mode")
                    content.image = UIImage(systemName: "circle.lefthalf.filled")
                    cell.accessoryView = switchWithValue(settingsSnapshot.keepIconsInDarkAndTinted, action: #selector(keepAppearanceChanged(_:)))
                }
            case .iconCache:
                content.text = LMLocalized("Clear icon cache & respring")
                content.textProperties.color = view.tintColor
                content.image = UIImage(systemName: "arrow.clockwise")
                cell.selectionStyle = .default
            case .troubleshooting:
                content.text = LMLocalized("Diagnostics")
                content.image = UIImage(systemName: "stethoscope")
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
            case .about:
                if indexPath.row == 0 {
                    content.text = LMLocalized("Version")
                    content.secondaryText = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                } else {
                    content.text = LMLocalized("Themes folder")
                    content.secondaryText = LMThemesDirectoryDisplayName
                    content.secondaryTextProperties.color = .secondaryLabel
                }
            default:
                break
        }

        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == LMSettingsSection.iconCache.rawValue {
            confirmClearIconCache()
        } else if indexPath.section == LMSettingsSection.troubleshooting.rawValue {
            navigationController?.pushViewController(LMDiagnosticsViewController(), animated: true)
        }
    }
}
