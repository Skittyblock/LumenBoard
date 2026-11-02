import UIKit

@objc(LMAppDelegate)
class LMAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = LMSceneDelegate.self
        return configuration
    }
}

class LMSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        window = UIWindow(windowScene: windowScene)
        let navigationController = UINavigationController(rootViewController: LMThemesViewController())
        navigationController.navigationBar.prefersLargeTitles = true
        navigationController.isToolbarHidden = false
        window?.tintColor = UIColor(red: 0.25, green: 0.56, blue: 0.98, alpha: 1.0)
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
    }
}
