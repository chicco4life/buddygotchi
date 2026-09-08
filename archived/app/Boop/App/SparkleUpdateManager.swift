import Foundation

@MainActor
final class SparkleUpdateManager {
    static let shared = SparkleUpdateManager()

    private var controller: NSObject?
    private(set) var isAvailable = false

    func start() {
        guard controller == nil else { return }
        loadBundledFrameworkIfNeeded()
        guard let controllerClass = NSClassFromString("SPUStandardUpdaterController") else {
            isAvailable = false
            #if DEBUG
            print("[Sparkle] Sparkle.framework not found; app updates disabled for this run.")
            #endif
            return
        }
        guard let object = instantiateUpdaterController(controllerClass) else {
            isAvailable = false
            #if DEBUG
            print("[Sparkle] Could not initialize SPUStandardUpdaterController.")
            #endif
            return
        }
        controller = object
        isAvailable = true
    }

    func checkForUpdates() {
        start()
        guard let updater = controller?
            .perform(NSSelectorFromString("updater"))?
            .takeUnretainedValue() as? NSObject else {
            return
        }
        updater.perform(NSSelectorFromString("checkForUpdates"))
    }

    private func loadBundledFrameworkIfNeeded() {
        guard NSClassFromString("SPUStandardUpdaterController") == nil,
              let privateFrameworksURL = Bundle.main.privateFrameworksURL else {
            return
        }
        let sparkleURL = privateFrameworksURL.appendingPathComponent("Sparkle.framework")
        if let bundle = Bundle(url: sparkleURL), !bundle.isLoaded {
            do {
                try bundle.loadAndReturnError()
            } catch {
                #if DEBUG
                print("[Sparkle] Failed to load Sparkle.framework: \(error)")
                #endif
            }
        }
    }

    private func instantiateUpdaterController(_ cls: AnyClass) -> NSObject? {
        let selector = NSSelectorFromString("initWithStartingUpdater:updaterDelegate:userDriverDelegate:")
        guard let method = class_getInstanceMethod(cls, selector) else { return nil }
        guard let allocated = (cls as? NSObject.Type)?
            .perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue() else {
            return nil
        }
        typealias InitFunction = @convention(c) (AnyObject, Selector, Bool, AnyObject?, AnyObject?) -> Unmanaged<AnyObject>
        let implementation = method_getImplementation(method)
        let initializer = unsafeBitCast(implementation, to: InitFunction.self)
        let initialized = initializer(allocated, selector, true, nil, nil).takeUnretainedValue()
        return initialized as? NSObject
    }
}
