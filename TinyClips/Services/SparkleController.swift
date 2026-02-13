import Foundation
import Security
import Combine
import AppKit

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
protocol UpdaterProviding: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var isAvailable: Bool { get }
    func checkForUpdates(_ sender: Any?)
}

final class DisabledUpdaterController: UpdaterProviding {
    var automaticallyChecksForUpdates: Bool = false
    var automaticallyDownloadsUpdates: Bool = false
    let isAvailable: Bool = false
    func checkForUpdates(_: Any?) {}
}

#if canImport(Sparkle)
extension SPUStandardUpdaterController: UpdaterProviding {
    var automaticallyChecksForUpdates: Bool {
        get { self.updater.automaticallyChecksForUpdates }
        set { self.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { self.updater.automaticallyDownloadsUpdates }
        set { self.updater.automaticallyDownloadsUpdates = newValue }
    }

    var isAvailable: Bool { true }
}
#endif

@MainActor
final class SparkleController: NSObject, ObservableObject {
    static let shared = SparkleController()

    private var updater: UpdaterProviding
    private let defaultsKey = "autoUpdateEnabled"

    @Published private(set) var isUpdateReady: Bool = false

    nonisolated(unsafe) private var updateStateSequence: Int = 0
    private let stateQueue = DispatchQueue(label: "com.tinyclips.sparkle.state")

    var canCheckForUpdates: Bool {
        updater.isAvailable
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            updater.automaticallyChecksForUpdates = newValue
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    override private init() {
        #if canImport(Sparkle)
        let bundleURL = Bundle.main.bundleURL
        let isBundledApp = bundleURL.pathExtension == "app"
        let isDevelopmentBuild = SparkleController.isDevelopmentBuild(bundleURL: bundleURL)
        let isSigned = SparkleController.isDeveloperIDSigned(bundleURL: bundleURL)
        let canUseSparkle = isBundledApp && isSigned && !isDevelopmentBuild
        #else
        let canUseSparkle = false
        #endif

        self.updater = DisabledUpdaterController()
        super.init()

        #if canImport(Sparkle)
        guard canUseSparkle else {
            print("[SparkleController] Disabled - not a signed release build")
            return
        }

        let savedAutoCheck = (UserDefaults.standard.object(forKey: defaultsKey) as? Bool) ?? false
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller.automaticallyChecksForUpdates = savedAutoCheck
        controller.automaticallyDownloadsUpdates = savedAutoCheck
        controller.startUpdater()
        self.updater = controller
        print("[SparkleController] Started with auto-check: \(savedAutoCheck)")
        #endif
    }

    func checkForUpdates() {
        guard canCheckForUpdates else {
            print("[SparkleController] Cannot check for updates - not available")
            return
        }
        updater.checkForUpdates(nil)
    }

    private static func isDevelopmentBuild(bundleURL: URL) -> Bool {
        let path = bundleURL.path
        return path.contains("DerivedData") ||
               path.contains("Xcode") ||
               path.contains("Build/Products")
    }

    private static func isDeveloperIDSigned(bundleURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let code = staticCode else {
            return false
        }

        var infoCF: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess else {
            return false
        }

        guard let info = infoCF as? [String: Any],
              let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certs.first else {
            return false
        }

        if let summary = SecCertificateCopySubjectSummary(leaf) as String? {
            return summary.hasPrefix("Developer ID Application:")
        }
        return false
    }
}

#if canImport(Sparkle)
extension SparkleController: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        let sequence = self.stateQueue.sync { () -> Int in
            self.updateStateSequence += 1
            return self.updateStateSequence
        }
        Task { @MainActor in
            let currentSequence = self.stateQueue.sync { self.updateStateSequence }
            guard sequence == currentSequence else { return }
            self.isUpdateReady = true
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        let sequence = self.stateQueue.sync { () -> Int in
            self.updateStateSequence += 1
            return self.updateStateSequence
        }
        Task { @MainActor in
            let currentSequence = self.stateQueue.sync { self.updateStateSequence }
            guard sequence == currentSequence else { return }
            self.isUpdateReady = false
        }
    }

    nonisolated func userDidCancelDownload(_ updater: SPUUpdater) {
        let sequence = self.stateQueue.sync { () -> Int in
            self.updateStateSequence += 1
            return self.updateStateSequence
        }
        Task { @MainActor in
            let currentSequence = self.stateQueue.sync { self.updateStateSequence }
            guard sequence == currentSequence else { return }
            self.isUpdateReady = false
        }
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        let downloaded = state.stage == .downloaded
        let sequence = self.stateQueue.sync { () -> Int in
            self.updateStateSequence += 1
            return self.updateStateSequence
        }
        Task { @MainActor in
            let currentSequence = self.stateQueue.sync { self.updateStateSequence }
            guard sequence == currentSequence else { return }
            switch choice {
            case .install, .skip:
                self.isUpdateReady = false
            case .dismiss:
                self.isUpdateReady = downloaded
            @unknown default:
                self.isUpdateReady = false
            }
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        let autoUpdateEnabled = UserDefaults.standard.bool(forKey: defaultsKey)
        guard autoUpdateEnabled else { return true }
        DispatchQueue.main.async {
            immediateInstallationBlock()
        }
        return false
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        print("[SparkleController] Installing update")
    }

    nonisolated func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        true
    }

    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        print("[SparkleController] Preparing for relaunch")
    }
}
#endif
