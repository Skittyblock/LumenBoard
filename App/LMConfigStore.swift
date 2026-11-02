import Darwin
import Foundation

// Config.plist, the only thing the app writes. SpringBoard turns it into the icon map on "Apply".
final class LMConfigStore: NSObject {
    static let shared = LMConfigStore()

    // theme folder names, highest priority first
    var enabledThemes: [String] = []
    var useSystemIconShape = false
    var keepIconsInDarkAndTinted = false

    private var appliedConfig: NSDictionary = [:]

    override init() {
        super.init()

        let data = try? Data(contentsOf: URL(fileURLWithPath: LMConfigPath))
        let config = data.flatMap {
            var format: PropertyListSerialization.PropertyListFormat = .xml
            return try? PropertyListSerialization.propertyList(
                from: $0,
                options: [],
                format: &format
            ) as? [String: Any]
        } ?? [:]

        let themes = config[LMConfigEnabledThemes]
        enabledThemes = themes as? [String] ?? []
        useSystemIconShape = (config[LMConfigUseSystemIconShape] as? Bool) ?? false
        keepIconsInDarkAndTinted = (config[LMConfigKeepIconsInDarkAndTinted] as? Bool) ?? false
        // what SpringBoard last applied, so the app knows about pending changes even after a restart
        let applied = NSDictionary(contentsOfFile: LMIconMapPath)?[LMMapAppliedConfig]
        appliedConfig = applied as? NSDictionary ?? dictionaryRepresentation()
    }

    // todo: don't want nsdictionary
    func dictionaryRepresentation() -> NSDictionary {
        [
            LMConfigEnabledThemes: enabledThemes,
            LMConfigUseSystemIconShape: useSystemIconShape,
            LMConfigKeepIconsInDarkAndTinted: keepIconsInDarkAndTinted
        ]
    }

    // changed since the last apply
    var hasUnappliedChanges: Bool {
        !dictionaryRepresentation().isEqual(appliedConfig)
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
}
