import Darwin
import Foundation

private func loadXML(fromPath path: String) -> [String: Any] {
    let data = try? Data(contentsOf: URL(fileURLWithPath: path))
    return data.flatMap {
        var format: PropertyListSerialization.PropertyListFormat = .xml
        return try? PropertyListSerialization.propertyList(
            from: $0,
            options: [],
            format: &format
        ) as? [String: Any]
    } ?? [:]
}

// Config.plist, the only thing the app writes. SpringBoard turns it into the icon map on "Apply".
actor LMConfigStore {
    static let shared = LMConfigStore()

    // theme folder names, highest priority first
    var enabledThemes: [String]
    var useSystemIconShape: Bool
    var keepIconsInDarkAndTinted: Bool

    private var appliedConfig: [String: Any] = [:]

    struct SettingsSnapshot: Sendable {
        var useSystemIconShape: Bool = false
        var keepIconsInDarkAndTinted: Bool = false
    }

    init() {
        let config = loadXML(fromPath: LMConfigPath)
        let themes = config[LMConfigEnabledThemes]
        let enabledThemes = themes as? [String] ?? []
        let useSystemIconShape = (config[LMConfigUseSystemIconShape] as? Bool) ?? false
        let keepIconsInDarkAndTinted = (config[LMConfigKeepIconsInDarkAndTinted] as? Bool) ?? false
        // what SpringBoard last applied, so the app knows about pending changes even after a restart
        let applied = loadXML(fromPath: LMIconMapPath)[LMMapAppliedConfig] as? [String: Any]
        appliedConfig = applied ?? [
            LMConfigEnabledThemes: enabledThemes,
            LMConfigUseSystemIconShape: useSystemIconShape,
            LMConfigKeepIconsInDarkAndTinted: keepIconsInDarkAndTinted
        ]
        self.enabledThemes = enabledThemes
        self.useSystemIconShape = useSystemIconShape
        self.keepIconsInDarkAndTinted = keepIconsInDarkAndTinted
    }

    func dictionaryRepresentation() -> [String: Any] {
        [
            LMConfigEnabledThemes: enabledThemes,
            LMConfigUseSystemIconShape: useSystemIconShape,
            LMConfigKeepIconsInDarkAndTinted: keepIconsInDarkAndTinted
        ]
    }

    // changed since the last apply
    var hasUnappliedChanges: Bool {
        !NSDictionary(dictionary: dictionaryRepresentation()).isEqual(NSDictionary(dictionary: appliedConfig))
    }

    func save() throws {
        try FileManager.default.createDirectory(atPath: LMDataDirectory, withIntermediateDirectories: true, attributes: nil)
        let data = try PropertyListSerialization.data(fromPropertyList: dictionaryRepresentation(), format: .binary, options: 0)
        try data.write(to: URL(fileURLWithPath: LMConfigPath), options: .atomic)
        LMConfigPath.withCString { path in
            _ = chmod(path, 0o644)
        }
    }

    func markApplied() {
        appliedConfig = dictionaryRepresentation()
    }

    func settingsSnapshot() -> SettingsSnapshot {
        .init(
            useSystemIconShape: useSystemIconShape,
            keepIconsInDarkAndTinted: keepIconsInDarkAndTinted
        )
    }

    func setEnabledThemes(_ enabledThemes: [String]) {
        self.enabledThemes = enabledThemes
    }

    func setUseSystemIconShape(_ useSystemIconShape: Bool) {
        self.useSystemIconShape = useSystemIconShape
    }

    func setKeepIconsInDarkAndTinted(_ keepIconsInDarkAndTinted: Bool) {
        self.keepIconsInDarkAndTinted = keepIconsInDarkAndTinted
    }
}
