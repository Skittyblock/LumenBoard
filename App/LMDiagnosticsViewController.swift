import UIKit

// The report is in English, it's meant to be pasted into a bug report.

private enum LMDiagnostics {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

func LMYesNo(_ value: Bool) -> String {
    value ? "yes" : "no"
}

func LMDateString(_ date: Any) -> String {
  guard let date = date as? Date else {
      return "-"
  }
  return LMDiagnostics.dateFormatter.string(from: date)
}

func LMExists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
}

func LMJailbreakName() -> String {
#if THEOS_PACKAGE_SCHEME_ROOTHIDE
    let scheme = "roothide"
#else
    let scheme = "rootless"
#endif
    let name = if LMExists("/cores/binpack") {
        "palera1n"
    } else if LMExists(LMRootPath("/.installed_dopamine")) {
        "Dopamine"
    } else if LMExists(LMRootPath("/.installed_nathanlr")) {
        "nathanlr"
    } else {
        "unknown"
    }
    return "\(name) (\(scheme))"
}

func LMTweakLoaderName() -> String {
    var loaders = [String]()
    if LMExists(LMRootPath("/usr/lib/libellekit.dylib")) {
        loaders.append("ElleKit")
    }
    if LMExists(LMRootPath("/usr/lib/libsubstitute.dylib")) {
        loaders.append("Substitute")
    }
    if LMExists(LMRootPath("/usr/lib/libhooker.dylib")) {
        loaders.append("libhooker")
    }
    if LMExists(LMRootPath("/usr/lib/TweakLoader.dylib")) {
        loaders.append("TweakLoader.dylib")
    }
    return loaders.isEmpty ? "none found" : loaders.joined(separator: ", ")
}

// what's really in a theme folder, for themes that come out with no icons
func LMFolderSummary(_ path: String) -> String {
    var info = stat()
    guard lstat(path, &info) == 0 else {
        if let error = strerror(errno).flatMap({ String(cString: $0) }) {
            return "missing (\(error))"
        } else {
            return "missing"
        }
    }

    var kind: String
    var entries: [String]?
    var error: NSError?
    if (info.st_mode & S_IFMT) == S_IFDIR {
        kind = "folder"
        do {
            entries = try FileManager.default.contentsOfDirectory(atPath: path).sorted()
        } catch let e as NSError {
            error = e
        }
    } else if (info.st_mode & S_IFMT) == S_IFLNK {
        kind = "symlink to \((try? FileManager.default.destinationOfSymbolicLink(atPath: path)) ?? "?")"
    } else {
        kind = "file"
    }

    var contents = "-"
    if let entries {
        let pngs = entries.filter { $0.lowercased().hasSuffix(".png") }.count
        let sample = entries.prefix(4).joined(separator: ", ")
        contents = "\(entries.count) entries, \(pngs) png: \(sample)"
    } else if let error {
        contents = error.localizedDescription
    }
    return "\(kind) \(String(Int(info.st_mode & 0o7777), radix: 8)) uid \(info.st_uid), \(contents)"
}

func LMStatus(_ name: String) -> [String: Any]? {
    let statusPath = LMStatusPath(name)
    guard let status = NSDictionary(contentsOfFile: statusPath) as? [String: Any] else {
        return nil
    }
    return status
}

func LMProcessRunning(_ status: [String: Any]) -> Bool {
    guard let pid = status["PID"] as? Int32 else {
        return false
    }
    return pid > 0 && kill(pid, 0) == 0
}

func LMCounter(_ status: [String: Any], _ counter: String) -> UInt64 {
    guard let counters = status[LMStatusCounters] as? [String: Any] else {
        return 0
    }
    return (counters[counter] as? NSNumber)?.uint64Value ?? 0
}

func LMAppendProcess(_ report: NSMutableString, _ name: String, _ status: [String: Any]?, _ missing: String) {
    report.append("\n\(name)\n")
    guard let status = status else {
        report.append("  no report: \(missing)\n")
        return
    }
    report.append("  loaded \(LMDateString(status[LMStatusLoaded] ?? "-")), updated \(LMDateString(status[LMStatusUpdated] ?? "-")), pid \(status["PID"] ?? "-") (\(LMProcessRunning(status) ? "running" : "not running"))\n")
    report.append("  hooks installed: \(LMYesNo(status[LMStatusHooksInstalled] as? Bool ?? false)), icons in map: \(status[LMStatusMapIcons] ?? "-")\n")
    if let agentRendersThemes = status[LMStatusAgentRendersThemes] as? Bool {
        report.append("  iconservicesagent renders theme icons: \(LMYesNo(agentRendersThemes))\n")
    }
    if let counters = status[LMStatusCounters] as? [String: Any] {
        let parts = counters.keys.sorted().map { "\($0) \(counters[$0] ?? "-")" }
        report.append("  \(parts.joined(separator: ", "))\n")
    }
    if let events = status[LMStatusEvents] as? [String] {
        for event in events {
            report.append("  - \(event)\n")
        }
    }
}

func LMDiagnosticsReport() async -> String {
    let report = NSMutableString()
    var name = utsname()
    uname(&name)
    let root = LMRootPath("")!
    report.append("LumenBoard \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "-")\n")
    let version = ProcessInfo.processInfo.operatingSystemVersion

    let machineMirror = Mirror(reflecting: name.machine)
    let machine = machineMirror.children.reduce("") { identifier, element in
        guard let value = element.value as? Int8, value != 0 else { return identifier }
        return identifier + String(UnicodeScalar(UInt8(value)))
    }

    report.append("\(machine), iOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)\n")
    report.append("Jailbreak: \(LMJailbreakName()), root \(root.isEmpty ? "/" : root) -> \(((root.isEmpty ? "/" : root) as NSString).resolvingSymlinksInPath)\n")
    report.append("Tweak loader: \(LMTweakLoaderName())\n")
    for tweak in ["LumenBoardCore", "LumenBoardSpringBoard"] {
        let base = LMRootPath("/Library/MobileSubstrate/DynamicLibraries").appending("/\(tweak)")
        report.append("\(tweak): dylib \(LMYesNo(LMExists(base + ".dylib"))), plist \(LMYesNo(LMExists(base + ".plist")))\n")
    }

    // what's going on in short
    let springBoard = LMStatus("SpringBoard")
    let agent = LMStatus("iconservicesagent")
    let apply = LMStatus("Apply")
    let map = NSDictionary(contentsOfFile: LMIconMapPath) as? [String:Any] ?? [:]
    let mapIcons = map[LMMapIcons] as? [String: Any] ?? [:]
    var findings = [String]()
    let enabledThemes = await LMConfigStore.shared.enabledThemes
    if enabledThemes.isEmpty {
        findings.append("No active theme.")
    }
    if apply == nil {
        findings.append("SpringBoard never applied a theme (Apply didn't reach LumenBoardSpringBoard).")
    }
    if !enabledThemes.isEmpty && mapIcons.isEmpty {
        findings.append("The icon map is empty: the active themes have no icons for installed apps.")
    }
    if springBoard == nil || !LMProcessRunning(springBoard!) {
        findings.append("LumenBoardCore isn't running in SpringBoard.")
    } else if springBoard?[LMStatusHooksInstalled] as? Bool != true {
        findings.append("LumenBoardCore runs in SpringBoard but couldn't hook IconServices.")
    } else if !mapIcons.isEmpty && LMCounter(springBoard!, "ThemedIcons") == 0 {
        findings.append("SpringBoard hasn't asked for a themed icon yet, respring once.")
    }
    if springBoard?[LMStatusAgentRendersThemes] as? Bool == false {
        findings.append("iconservicesagent renders without the theme, SpringBoard renders the theme icons itself.")
    }
    if LMCounter(springBoard ?? [:], "UnreadableImages") > 0 || LMCounter(agent ?? [:], "UnreadableImages") > 0 {
        findings.append("Some theme images couldn't be loaded.")
    }
    if LMCounter(springBoard ?? [:], "LocalFailed") > 0 {
        findings.append("Some icons couldn't be rendered with the theme.")
    }
    report.append("\nFindings\n")
    if findings.isEmpty {
        findings.append("Nothing obviously wrong.")
    }
    for finding in findings {
        report.append("  - \(finding)\n")
    }

    // themes
    LMThemeLibrary.invalidate()
    let installed = LMThemeLibrary.installedThemes()
    report.append("\nThemes in \(LMThemesDirectory): \(installed.count) installed, \(enabledThemes.count) active (*)\n")
    var themes = installed
    for theme in enabledThemes where !themes.contains(theme) {
        themes.append(theme)
    }
    for theme in themes {
        let byBundleID = LMThemeLibrary.icons(inTheme: theme).count
        let byName = LMThemeLibrary.iconsByAppName(inTheme: theme).count
        let error = LMThemeLibrary.readError(forTheme: theme)
        let state: String
        if !installed.contains(theme) {
            state = " (not installed)"
        } else if let error = error {
            state = " (\(error))"
        } else {
            state = ""
        }
        report.append("  \(enabledThemes.contains(theme) ? "* " : "")\(theme): \(byBundleID) by bundle id, \(byName) by app name\(state)\n")
        if byBundleID + byName > 0 || !installed.contains(theme) {
            continue
        }
        let directory = LMThemesDirectory.appending("/\(theme)")
        report.append("      theme: \(LMFolderSummary(directory))\n")
        for folder in ["IconBundles", "Icons"] {
            report.append("      \(folder): \(LMFolderSummary(directory.appending("/\(folder)")))\n")
        }
    }
    let useSystemIconShape = await LMConfigStore.shared.useSystemIconShape
    let keepIconsInDarkAndTinted = await LMConfigStore.shared.keepIconsInDarkAndTinted
    report.append("  iOS icon shape: \(LMYesNo(useSystemIconShape)), keep in dark & tinted: \(LMYesNo(keepIconsInDarkAndTinted))\n")

    // icon map
    let mapExists = LMExists(LMIconMapPath)
    report.append("\nIcon map: \(mapExists ? "\(mapIcons.count) icons, version \(map["Version"] ?? "-"), written \(LMDateString((try? FileManager.default.attributesOfItem(atPath: LMIconMapPath)[.modificationDate]) ?? "-"))" : "missing")\n")
    let sample = Array(mapIcons.keys.sorted().prefix(3))
    for bundleID in sample {
        let path = (mapIcons[bundleID] as? [String: Any])?[LMIconLight] as? String
        let image: UIImage? = {
            guard let path = path else { return nil }
            return UIImage(contentsOfFile: LMRootPath(path))
        }()
        report.append("  \(bundleID) -> \(path ?? "-") (\(image != nil ? "\(Int(image!.size.width * image!.scale))x\(Int(image!.size.height * image!.scale)) px" : "can't load"))\n")
    }

    // last apply
    report.append("\nLast apply\n")
    if let apply {
        report.append("  \(LMDateString(apply["Date"] ?? "-")), clear cache \(LMYesNo(apply["ClearCache"] as? Bool ?? false)), map changed \(LMYesNo(apply["MapChanged"] as? Bool ?? false)), \(apply["MapIcons"] ?? "-") icons in map\n")
        report.append("  pre-rendered \(apply["Prerendered"] ?? "-") of \(apply["AppsToRender"] ?? "-") apps (\(apply["Descriptors"] ?? "-") sizes), respring: \(apply["Respring"] ?? "-")\n")
    } else {
        report.append("  none\n")
    }

    LMAppendProcess(report, "SpringBoard", springBoard, "LumenBoardCore isn't loaded in SpringBoard")
    LMAppendProcess(report, "iconservicesagent", agent, "not loaded there, or not allowed to write (normal on Dopamine)")

    return report as String
}

// Report about the jailbreak, the themes, the icon map and what the tweak did in SpringBoard and iconservicesagent.
final class LMDiagnosticsViewController: UIViewController {
    private var textView: UITextView?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = LMLocalized("Diagnostics")
        self.navigationItem.largeTitleDisplayMode = .never
        self.view.backgroundColor = .systemBackground

        textView = UITextView()
        textView?.isEditable = false
        textView?.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView?.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        textView?.alwaysBounceVertical = true
        textView?.translatesAutoresizingMaskIntoConstraints = false
        if let textView = textView {
            self.view.addSubview(textView)
            NSLayoutConstraint.activate([
                textView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
                textView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
                textView.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor),
            ])
        }

        let copy = UIBarButtonItem(image: UIImage(systemName: "doc.on.doc"), style: .plain, target: self, action: #selector(copyReport))
        copy.accessibilityLabel = LMLocalized("Copy report")
        let refresh = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(reload))
        self.navigationItem.rightBarButtonItems = [copy, refresh]
        self.reload()
    }

    @objc
    func reload() {
        textView?.text = LMLocalized("Loading…")
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                await LMDiagnosticsReport()
            }.value
            self.textView?.text = report
        }
    }

    @objc
    func copyReport() {
        UIPasteboard.general.string = textView?.text
        let alert = UIAlertController(
            title: LMLocalized("Report copied"),
            message: LMLocalized("Paste it wherever you ask for help."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: LMLocalized("OK"), style: .cancel, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
}
