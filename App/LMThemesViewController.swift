import Darwin
import ImageIO
import UIKit

private enum LMThemeSection: Int {
    case active
    case installed
}

// shown in the theme previews when the theme has them
private func LMPreviewApps() -> [String] {
    return ["com.apple.mobilesafari", "com.apple.mobilesms", "com.apple.mobilephone", "com.apple.camera",
            "com.apple.mobileslideshow", "com.apple.preferences", "com.apple.appstore", "com.apple.mobilemail"]
}

// decodes only what the preview needs, theme icons are often 1024 px
private func LMThumbnail(_ path: String, _ pixels: CGFloat) -> UIImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path, isDirectory: false) as CFURL, nil) else {
        return nil
    }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: pixels,
    ]
    let image = CGImageSourceGetCount(source) > 0 ? CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) : nil
    guard let image else { return nil }
    return UIImage(cgImage: image)
}

// changes when the theme is reinstalled or icons are added or removed
private func LMThemeStamp(_ theme: String) -> String {
    let directory = (LMThemesDirectory as NSString).appendingPathComponent(theme)
    let stamp = NSMutableString()
    for folder in ["", "IconBundles", "Icons"] {
        var info = stat()
        if stat((directory as NSString).appendingPathComponent(folder), &info) == 0 {
            stamp.appendFormat("%lld.%ld/", info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec)
        } else {
            stamp.append("-/")
        }
    }
    return stamp as String
}

private func LMRenderPreview(_ paths: [String]) -> UIImage? {
    let side: CGFloat = 44, gap: CGFloat = 3
    let count = min(paths.count, 4)
    let tile = count == 1 ? side : (side - gap) / 2
    var icons: [UIImage] = []
    for index in 0..<count {
        if let icon = LMThumbnail(paths[index], tile * 3) { icons.append(icon) }
    }
    guard !icons.isEmpty else { return nil }
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
    return renderer.image { context in
        for index in 0..<icons.count {
            let icon = icons[index]
            let rect = count == 1 ? CGRect(x: 0, y: 0, width: side, height: side) : CGRect(x: CGFloat(index % 2) * (tile + gap), y: CGFloat(index / 2) * (tile + gap), width: tile, height: tile)
            context.cgContext.saveGState()
            UIBezierPath(roundedRect: rect, cornerRadius: tile * 0.225).addClip()
            icon.draw(in: rect)
            context.cgContext.restoreGState()
        }
    }
}

// Main screen: installed themes, which ones are active and in what order.
final class LMThemesViewController: UITableViewController {
    private var active: [String] = []
    private var installed: [String] = []
    // theme -> preview, icon count and the stamp they were loaded with
    private var details: [String: [String: Any]] = [:]
    private var loading: Set<String> = []
    private var detailsQueue: DispatchQueue!
    private var changeTimer: Timer?
    private var applyButton: UIButton!

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "LumenBoard"
        details = [:]
        loading = []
        // one theme at a time, so the visible ones are done first
        detailsQueue = DispatchQueue(label: "com.xsxs18.lumenboard.theme-details", qos: .userInitiated)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Theme")
        tableView.rowHeight = 64
        tableView.allowsSelectionDuringEditing = true

        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: self, action: #selector(showSettings))
        navigationItem.rightBarButtonItem = editButtonItem

        var configuration = UIButton.Configuration.filled()
        configuration.title = LMLocalized("Apply")
        configuration.image = UIImage(systemName: "square.grid.2x2")
        configuration.imagePadding = 8
        configuration.cornerStyle = .capsule
        configuration.buttonSize = .large
        configuration.titleAlignment = .center
        applyButton = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.apply()
        })
        let space = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbarItems = [space, UIBarButtonItem(customView: applyButton), space]

        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadThemes), name: UIApplication.willEnterForegroundNotification, object: nil)
        reloadThemes()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // the package manager may still be installing themes in the background
        changeTimer?.invalidate()
        changeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkForThemeChanges()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        changeTimer?.invalidate()
        changeTimer = nil
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
        updateApplyButton()
    }
}

// MARK: Data
extension LMThemesViewController {
    @objc private func reloadThemes() {
        LMThemeLibrary.invalidate()
        let installed = LMThemeLibrary.installedThemes()
        var active: [String] = []
        for theme in LMConfigStore.shared.enabledThemes {
            if installed.contains(theme) && !active.contains(theme) { active.append(theme) }
        }
        self.active = active
        self.installed = installed
        self.installed.removeAll { active.contains($0) }
        // keep the previews of themes whose files didn't change, try the ones that couldn't be read again
        for theme in Array(details.keys) {
            if !installed.contains(theme) || details[theme]?["Error"] != nil || details[theme]?["Stamp"] as? String != LMThemeStamp(theme) {
                details.removeValue(forKey: theme)
            }
        }
        // themes that were uninstalled drop out of the configuration
        if active != LMConfigStore.shared.enabledThemes {
            saveActiveThemes()
        }

        refreshControl?.endRefreshing()
        tableView.reloadData()
        updateEmptyState()
        updateApplyButton()
    }

    // pull to refresh: read every theme again
    @objc private func refresh() {
        details.removeAll()
        reloadThemes()
    }

    private func checkForThemeChanges() {
        guard !tableView.isEditing else { return }
        var known = Set(active)
        known.formUnion(installed)
        if Set(LMThemeLibrary.installedThemes()) != known {
            reloadThemes()
            return
        }
        // icons added or removed since the preview was made
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            guard
                let theme = theme(at: indexPath),
                let themeDetails = details[theme],
                themeDetails["Stamp"] as? String != LMThemeStamp(theme)
            else {
                continue
            }
            details.removeValue(forKey: theme)
            LMThemeLibrary.invalidateTheme(theme)
            if let cell = tableView.cellForRow(at: indexPath) {
                configureCell(cell, at: indexPath)
            }
        }
    }

    private func theme(at indexPath: IndexPath) -> String? {
        let themes = indexPath.section == LMThemeSection.active.rawValue ? active : installed
        return indexPath.row < themes.count ? themes[indexPath.row] : nil
    }

    @discardableResult
    private func saveActiveThemes() -> Bool {
        LMConfigStore.shared.enabledThemes = active
        do {
            try LMConfigStore.shared.save()
            updateApplyButton()
            return true
        } catch {
            let alert = UIAlertController(title: LMLocalized("Couldn't save"), message: String(format: LMLocalized("%@\n\nLumenBoard has to be installed as a package (not as an IPA) so it can write its settings."), error.localizedDescription), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: LMLocalized("OK"), style: .cancel))
            present(alert, animated: true)
            return false
        }
    }

    private func loadDetails(for theme: String?) {
        guard let theme, !loading.contains(theme) else { return }
        loading.insert(theme)
        detailsQueue.async {
            let stamp = LMThemeStamp(theme)
            let icons = LMThemeLibrary.icons(inTheme: theme)
            var paths: [String] = []
            for bundleID in LMPreviewApps() {
                if let path = icons[bundleID]?[LMIconLight] as? String, paths.count < 4 { paths.append(path) }
            }
            for bundleID in icons.keys.sorted() {
                if paths.count >= 4 { break }
                if let path = icons[bundleID]?[LMIconLight] as? String, !paths.contains(path) { paths.append(path) }
            }
            var details: [String: Any] = [:]
            details["Stamp"] = stamp
            details["Count"] = icons.count + LMThemeLibrary.iconsByAppName(inTheme: theme).count
            details["Error"] = LMThemeLibrary.readError(forTheme: theme)
            details["Preview"] = LMRenderPreview(paths)
            DispatchQueue.main.async {
                self.loading.remove(theme)
                self.details[theme] = details
                // update the cell on screen itself, a dequeued cell would be a different one
                for indexPath in self.tableView.indexPathsForVisibleRows ?? [] {
                    if self.theme(at: indexPath) != theme { continue }
                    if let cell = self.tableView.cellForRow(at: indexPath) {
                        self.configureCell(cell, at: indexPath)
                    }
                }
            }
        }
    }
}

// MARK: UI state
extension LMThemesViewController {
    private func updateEmptyState() {
        if active.count + installed.count > 0 {
            tableView.backgroundView = nil
            return
        }
        let image = UIImageView(image: UIImage(systemName: "square.grid.2x2", withConfiguration: UIImage.SymbolConfiguration(pointSize: 48, weight: .light)))
        image.tintColor = .tertiaryLabel
        let title = UILabel()
        title.text = LMLocalized("No themes installed")
        title.font = .preferredFont(forTextStyle: .title3)
        let detail = UILabel()
        detail.text = String(format: LMLocalized("Install themes from your package manager. They are stored in %@."), LMThemesDirectoryDisplayName)
        detail.font = .preferredFont(forTextStyle: .subheadline)
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0
        detail.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [image, title, detail])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let background = UIView()
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: background.centerYAnchor, constant: -40),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -32),
        ])
        tableView.backgroundView = background
    }

    private func updateApplyButton() {
        var configuration = applyButton.configuration
        configuration?.subtitle = LMConfigStore.shared.hasUnappliedChanges ? LMLocalized("Changes not applied yet") : nil
        applyButton.configuration = configuration
        applyButton.sizeToFit()
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
    }
}

// MARK: Actions
extension LMThemesViewController {
    @objc private func showSettings() {
        navigationController?.pushViewController(LMSettingsViewController(), animated: true)
    }

    private func apply() {
        if !saveActiveThemes() { return }
        present(LMApplyViewController(clearingIconCache: false)!, animated: true) {
            self.updateApplyButton()
        }
    }
}

// MARK: Table view
extension LMThemesViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        active.count + installed.count > 0 ? 2 : 0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == LMThemeSection.active.rawValue ? active.count : installed.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == LMThemeSection.active.rawValue ? LMLocalized("Active") : LMLocalized("Installed")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == LMThemeSection.active.rawValue {
            return !active.isEmpty ? LMLocalized("When several themes have an icon for the same app, the one higher up wins. Tap Edit to change the order.") : LMLocalized("Tap a theme below to activate it.")
        }
        return !installed.isEmpty ? nil : LMLocalized("All installed themes are active.")
    }

    private func configureCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        let theme = theme(at: indexPath)
        let details = theme.flatMap { details[$0] }
        if details == nil { loadDetails(for: theme) }

        var content = UIListContentConfiguration.subtitleCell()
        content.text = theme.map { LMThemeLibrary.displayName(forTheme: $0) }
        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        if details?["Error"] != nil {
            content.secondaryText = LMLocalized("Couldn't read this theme, pull down to try again")
        } else if let details {
            content.secondaryText = String.localizedStringWithFormat(LMLocalized("%lu icons"), (details["Count"] as? NSNumber)?.uintValue ?? 0)
        } else {
            content.secondaryText = LMLocalized("Loading…")
        }
        content.secondaryTextProperties.color = .secondaryLabel
        content.image = details?["Preview"] as? UIImage ?? UIImage(systemName: "square.grid.2x2")
        content.imageProperties.maximumSize = CGSize(width: 44, height: 44)
        content.imageProperties.reservedLayoutSize = CGSize(width: 44, height: 44)
        content.imageProperties.tintColor = .tertiaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = indexPath.section == LMThemeSection.active.rawValue ? .checkmark : .none
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Theme", for: indexPath)
        cell.showsReorderControl = indexPath.section == LMThemeSection.active.rawValue
        configureCell(cell, at: indexPath)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let theme = theme(at: indexPath) else { return }
        let destination: IndexPath
        if indexPath.section == LMThemeSection.active.rawValue {
            active.remove(at: indexPath.row)
            let position = (installed as NSArray).index(of: theme, inSortedRange: NSRange(location: 0, length: installed.count), options: .insertionIndex) { a, b in
                return LMThemeLibrary.displayName(forTheme: a as! String).localizedCaseInsensitiveCompare(LMThemeLibrary.displayName(forTheme: b as! String))
            }
            installed.insert(theme, at: position)
            destination = IndexPath(row: position, section: LMThemeSection.installed.rawValue)
        } else {
            installed.remove(at: indexPath.row)
            active.append(theme)
            destination = IndexPath(row: active.count - 1, section: LMThemeSection.active.rawValue)
        }
        tableView.performBatchUpdates {
            tableView.moveRow(at: indexPath, to: destination)
        } completion: { _ in
            tableView.reloadSections(IndexSet(integersIn: 0..<2), with: .none)
        }
        saveActiveThemes()
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == LMThemeSection.active.rawValue
    }

    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt source: IndexPath, toProposedIndexPath proposed: IndexPath) -> IndexPath {
        if proposed.section == LMThemeSection.active.rawValue {
            return proposed
        }
        return IndexPath(row: active.isEmpty ? 0 : active.count - 1, section: LMThemeSection.active.rawValue)
    }

    override func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        let theme = active[source.row]
        active.remove(at: source.row)
        active.insert(theme, at: destination.row)
        saveActiveThemes()
    }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        .none
    }

    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        false
    }
}
