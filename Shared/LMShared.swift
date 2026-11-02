import Foundation

let LMThemesDirectory: String = LMRootPath("/Library/Themes")!
#if THEOS_PACKAGE_SCHEME_ROOTHIDE
let LMThemesDirectoryDisplayName: String = "/Library/Themes"
#else
let LMThemesDirectoryDisplayName: String = LMThemesDirectory
#endif

// Config.plist (app) and IconMap.plist (SpringBoard). Not in /var/mobile/Library/Preferences because
// iconservicesagent is sandboxed and can only read from the jailbreak folder.
let LMDataDirectory: String = LMRootPath("/var/mobile/Library/LumenBoard")!
let LMConfigPath: String = LMDataDirectory + "/Config.plist"
let LMIconMapPath: String = LMDataDirectory + "/IconMap.plist"

let LMNotifyApply = "com.xsxs18.lumenboard/apply"
let LMNotifyClearCache = "com.xsxs18.lumenboard/clear-cache"
let LMNotifyMapChanged = "com.xsxs18.lumenboard/map-changed"
// state = (done << 32) | total, done == UINT32_MAX when SpringBoard is about to respring
let LMNotifyProgress = "com.xsxs18.lumenboard/progress"

// Config.plist
let LMConfigEnabledThemes = "EnabledThemes" // theme folder names, first one wins
let LMConfigUseSystemIconShape = "UseSystemIconShape"
let LMConfigKeepIconsInDarkAndTinted = "KeepIconsInDarkAndTinted"

// IconMap.plist
let LMMapVersion = 2 // 2: icon paths are jailbreak paths
let LMMapIcons = "Icons" // lowercased bundle id -> icon
let LMIconLight = "Light"
let LMIconDark = "Dark"
let LMIconTinted = "Tinted"
let LMIconToken = "Token" // changes whenever the icon or the settings change
let LMMapAppliedConfig = "AppliedConfig"

// Status-<name>.plist: what the tweak did in SpringBoard, in iconservicesagent and on the last apply. Shown on the diagnostics page.
func LMStatusPath(_ name: String) -> String {
    LMDataDirectory + "/Status-\(name).plist"
}
let LMStatusLoaded: String = "Loaded"
let LMStatusUpdated: String = "Updated"
let LMStatusHooksInstalled: String = "HooksInstalled"
let LMStatusAgentRendersThemes: String = "AgentRendersThemes" // NO: SpringBoard renders the theme icons itself
let LMStatusMapIcons: String = "MapIcons"
let LMStatusCounters: String = "Counters"
let LMStatusEvents: String = "Events"

func LMLocalized(_ text: String) -> String {
    NSLocalizedString(text, comment: "")
}
