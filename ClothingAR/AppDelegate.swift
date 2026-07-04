import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 启动时清理上一次可能残留的临时文件
        cleanTemporaryFiles()
        return true
    }

    // MARK: - UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {}

    // MARK: - Cleanup

    func applicationWillTerminate(_ application: UIApplication) {
        cleanTemporaryFiles()
    }

    /// 清理临时目录下的旧录制文件，避免存储空间被占满
    private func cleanTemporaryFiles() {
        let tempDir = NSTemporaryDirectory()
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: tempDir) else { return }
        for file in contents where file.hasSuffix(".mp4") {
            let path = (tempDir as NSString).appendingPathComponent(file)
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
