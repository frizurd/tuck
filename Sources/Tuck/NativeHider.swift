import AppKit
import ApplicationServices
import OSLog
import TuckCore
import TuckPrivate

private let log = Logger(subsystem: "com.frizurd.tuck", category: "native")

/// Hiding on macOS 27 and later without stretching anything.
///
/// Tuck reads which app owns each menu bar icon and where it sits (Accessibility), then
/// asks macOS to allow only the apps on the visible side, through the menu bar
/// restriction behind macOS's assessment mode. macOS hides the rest and reflows the bar
/// itself, so there's no `«` and nothing depends on the notch or the app menus.
/// Idea and bridge from Hidden Bar (MIT): https://github.com/dwarvesf/hidden
///
/// Limits, all from what macOS exposes: hiding is per app, so an app's icons hide
/// together; and macOS's own icons (Wi-Fi, clock, Control Center) always stay visible.
@MainActor
final class NativeHider {
    /// Unknown identifiers are ignored, so this keeps every system item visible.
    private static let systemItems = (0..<64).map { NSNumber(value: $0) }

    static let isSupported: Bool =
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 && TuckMenuBarVisibilityIsAvailable()

    var isUsable: Bool { Self.isSupported && AXIsProcessTrusted() }

    /// Sections read from an unrestricted bar. Hidden icons report stale positions, so
    /// these are only refreshed while nothing is restricted.
    private(set) var sections: [String: Section]?
    private var assertion: AnyObject?
    private var allowedNow: [String]?
    private var generation = 0
    private var reading = false
    private var afterRead: [() -> Void] = []
    private let ownBundle = Bundle.main.bundleIdentifier

    /// Re-reads the sections if nothing is restricted. Calls back once the read finishes.
    func refreshSections(chevronMidX: CGFloat, alwaysHiddenMidX: CGFloat?, then done: (() -> Void)? = nil) {
        if let done { afterRead.append(done) }
        guard assertion == nil else { return finishRead() }
        guard !reading else { return }
        reading = true
        let own = ownBundle
        StatusIconInventory.snapshot { [weak self] icons in
            guard let self else { return }
            reading = false
            sections = Sections.resolve(icons, chevronMidX: chevronMidX, alwaysHiddenMidX: alwaysHiddenMidX, ownBundle: own)
            log.debug("sections \(String(describing: self.sections), privacy: .public)")
            finishRead()
        }
    }

    private func finishRead() {
        guard !reading else { return }
        let callbacks = afterRead
        afterRead = []
        callbacks.forEach { $0() }
    }

    /// Applies a state. `completion(false)` means hiding failed and nothing is hidden.
    func apply(_ state: BarState, chevronMidX: CGFloat, alwaysHiddenMidX: CGFloat?,
               completion: @escaping (Bool) -> Void) {
        let hidesAnything = state == .hidden || (state == .shown && alwaysHiddenMidX != nil)
        guard hidesAnything else {
            release()
            return completion(true)
        }
        // Wait for a read in progress, so icons dragged a moment ago land in the right place.
        let needsRead = sections == nil || reading
        guard !needsRead else {
            refreshSections(chevronMidX: chevronMidX, alwaysHiddenMidX: alwaysHiddenMidX) { [weak self] in
                guard let self, sections != nil else { return completion(false) }
                apply(state, chevronMidX: chevronMidX, alwaysHiddenMidX: alwaysHiddenMidX, completion: completion)
            }
            return
        }
        // Showing with an always-hidden section that holds nothing: lift the restriction
        // instead of freezing the list of allowed apps.
        if state == .shown, !(sections ?? [:]).values.contains(.alwaysHidden) {
            release()
            return completion(true)
        }
        let allowed = (ownBundle.map { [$0] } ?? []) + Sections.allowed(sections ?? [:], in: state)
        guard allowed != allowedNow else { return completion(true) }
        activate(allowed, completion: completion)
    }

    /// The new restriction goes up before the old one comes down, so switching between
    /// states never flashes every icon.
    private func activate(_ allowed: [String], completion: @escaping (Bool) -> Void) {
        generation += 1
        let generation = self.generation
        TuckMenuBarVisibilityActivate(Self.systemItems, allowed) { [weak self] newAssertion, error in
            guard let self, generation == self.generation else {
                if let newAssertion { TuckMenuBarVisibilityInvalidate(newAssertion) }
                return
            }
            guard let newAssertion else {
                log.error("restriction failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                release()
                return completion(false)
            }
            log.debug("restricted to \(allowed, privacy: .public)")
            let old = assertion
            assertion = newAssertion as AnyObject
            allowedNow = allowed
            if let old { TuckMenuBarVisibilityInvalidate(old) }
            completion(true)
        }
    }

    /// Shows everything. macOS also lifts the restriction by itself if Tuck quits.
    func release() {
        if assertion != nil { log.debug("restriction lifted") }
        generation += 1
        if let assertion { TuckMenuBarVisibilityInvalidate(assertion) }
        assertion = nil
        allowedNow = nil
    }
}

/// Every other app's status icons, through public Accessibility API.
enum StatusIconInventory {
    static func snapshot(completion: @escaping @MainActor ([StatusIcon]) -> Void) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // Only app bundles own status items; skipping helpers keeps the walk near a second.
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID && $0.bundleURL?.pathExtension == "app" }
            .compactMap { app in app.bundleIdentifier.map { (pid: app.processIdentifier, bundle: $0) } }
        DispatchQueue.global(qos: .userInitiated).async {
            var icons: [StatusIcon] = []
            for app in apps {
                let element = AXUIElementCreateApplication(app.pid)
                // A busy app would otherwise stall the whole walk for seconds.
                AXUIElementSetMessagingTimeout(element, 0.1)
                var bar: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &bar) == .success,
                      let bar else { continue }
                var children: CFTypeRef?
                guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
                      let items = children as? [AXUIElement] else { continue }
                for item in items {
                    if let midX = midX(of: item) { icons.append(StatusIcon(bundleIdentifier: app.bundle, midX: midX)) }
                }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(icons) } }
        }
    }

    /// Accessibility uses a top-left origin; x matches AppKit's, which is all sections need.
    private static func midX(of element: AXUIElement) -> CGFloat? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return point.x + extent.width / 2
    }
}
