import AppKit
import Combine
import OSLog
import SwiftUI
import TuckCore

/// Owns Tuck's three status items and the hide/show state.
///
/// Layout, right to left: `‹ chevron` · `│ divider` · hidden icons · `┆ always-hidden divider` · always-hidden icons.
/// Hiding widens a divider to 10,000 pt so the icons on its left slide off screen.
private let log = Logger(subsystem: "com.frizurd.tuck", category: "menubar")

@MainActor
final class MenuBarController: NSObject {
    var openSettings: () -> Void = {}
    var openWelcome: () -> Void = {}

    private(set) var visibility: BarState = .shown
    private let preferences: Preferences
    private let toggleItem: NSStatusItem
    private let dividerItem: NSStatusItem
    private var alwaysHiddenItem: NSStatusItem?
    private var hideTimer: Timer?
    private var scrollMonitors: [Any] = []
    private var scrollGesture = ScrollGesture()
    private var misplacedPopover: NSPopover?
    private var subscriptions = Set<AnyCancellable>()

    /// Width of a visible divider: wide enough to grab while ⌘-dragging.
    private let dividerWidth: CGFloat = 14

    init(preferences: Preferences) {
        self.preferences = preferences
        // New status items appear left of existing ones, so create right to left.
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        dividerItem = NSStatusBar.system.statusItem(withLength: 14)
        super.init()

        toggleItem.autosaveName = "tuck.toggle"
        dividerItem.autosaveName = "tuck.divider"
        configure(toggleItem, label: "Tuck", action: #selector(toggleClicked))
        configure(dividerItem, label: "Tuck divider", action: #selector(dividerClicked))
        dividerItem.button?.image = Glyphs.divider
        dividerItem.button?.toolTip = "Icons left of this line are hidden.\n⌘-drag icons across it to choose."

        if preferences.alwaysHiddenSection { addAlwaysHiddenItem() }
        observePreferences()
        // Displays come and go, and the notch only exists on the built-in one.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                apply(visibility, explainIfMisplaced: false)
            }
            .store(in: &subscriptions)
        updateToggleAppearance()

        // Let the menu bar lay the items out before measuring their positions.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.apply(.hidden, explainIfMisplaced: false)
        }
    }

    // MARK: Commands

    func perform(_ command: Command) {
        guard let target = command.target(from: visibility) else { return }
        apply(target)
    }

    func apply(_ target: BarState, explainIfMisplaced: Bool = true) {
        let positions = currentPositions()
        if target != .showingAll, let positions, !positions.dividerIsUsable {
            // Hiding now would push the chevron itself off screen.
            apply(lengths: DividerLengths(divider: nil, alwaysHiddenDivider: nil))
            visibility = .shown
            updateToggleAppearance()
            if explainIfMisplaced { explainMisplacedDivider() }
            return
        }
        let lengths = positions.map { DividerLengths.resolve(target, positions: $0, push: pushLength) }
            ?? DividerLengths(divider: nil, alwaysHiddenDivider: nil)
        apply(lengths: lengths)
        log.debug("state \(String(describing: target), privacy: .public) positions \(String(describing: positions), privacy: .public)")
        visibility = target
        updateToggleAppearance()
        scheduleAutoHide(after: preferences.autoHideDelay)
    }

    private func apply(lengths: DividerLengths) {
        dividerItem.length = lengths.divider ?? dividerWidth
        alwaysHiddenItem?.length = lengths.alwaysHiddenDivider ?? dividerWidth
    }

    private func currentPositions() -> ItemPositions? {
        guard let toggle = toggleItem.button?.window?.frame,
              let divider = dividerItem.button?.window?.frame else { return nil }
        let alwaysHidden = alwaysHiddenItem?.button?.window?.frame
        return ItemPositions(toggle: toggle.minX, divider: divider.minX, dividerMaxX: divider.maxX,
                             alwaysHiddenDivider: alwaysHidden?.minX, alwaysHiddenDividerMaxX: alwaysHidden?.maxX)
    }

    /// The width that pushes every icon left of a divider out of the menu bar.
    private func pushLength(dividerMaxX: CGFloat) -> CGFloat {
        let screen = toggleItem.button?.window?.screen ?? NSScreen.main
        let target = screen.map {
            PushLength.targetLeftEdge(screen: $0.frame, notchLeftArea: $0.auxiliaryTopLeftArea,
                                      notchRightArea: $0.auxiliaryTopRightArea)
        } ?? 0
        let legacy = !ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
        return PushLength.compute(dividerMaxX: dividerMaxX, targetLeftEdge: target, legacy: legacy)
    }

    // MARK: Clicks

    @objc private func toggleClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu(from: toggleItem)
        } else if event.modifierFlags.contains(.option) {
            apply(visibility == .showingAll ? .hidden : .showingAll)
        } else {
            apply(visibility.isRevealed ? .hidden : .shown)
        }
    }

    /// Before macOS 26 the stretched divider fills the empty menu bar, so clicking empty space reveals icons.
    @objc private func dividerClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu(from: dividerItem)
        } else {
            apply(visibility.isRevealed ? .hidden : .shown)
        }
    }

    private func configure(_ item: NSStatusItem, label: String, action: Selector) {
        guard let button = item.button else { return }
        button.target = self
        button.action = action
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel(label)
    }

    private func updateToggleAppearance() {
        guard let button = toggleItem.button else { return }
        button.image = Glyphs.chevron(for: visibility)
        switch visibility {
        case .hidden:
            button.setAccessibilityLabel("Show hidden menu bar icons")
            button.toolTip = preferences.alwaysHiddenSection
                ? "Click to show hidden icons\n⌥-click to show everything\nRight-click for options"
                : "Click to show hidden icons\nRight-click for options"
        case .shown, .showingAll:
            button.setAccessibilityLabel("Hide menu bar icons")
            button.toolTip = "Click to hide icons\nRight-click for options"
        }
    }

    // MARK: Menu

    private func showMenu(from item: NSStatusItem) {
        let menu = NSMenu()
        let revealTitle = visibility.isRevealed ? "Hide Icons" : "Show Hidden Icons"
        menu.addItem(menuItem(revealTitle, #selector(menuToggle), key: ""))
        if preferences.alwaysHiddenSection {
            let all = menuItem("Show All Icons", #selector(menuShowAll), key: "")
            all.state = visibility == .showingAll ? .on : .off
            menu.addItem(all)
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", #selector(menuSettings), key: ","))
        menu.addItem(menuItem("How to Use Tuck", #selector(menuWelcome), key: ""))
        menu.addItem(menuItem("About Tuck", #selector(menuAbout), key: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Tuck", #selector(menuQuit), key: "q"))

        // Attaching the menu only for this click keeps left-click free for toggling.
        hideTimer?.invalidate()
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
        scheduleAutoHide(after: preferences.autoHideDelay)
    }

    private func menuItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    @objc private func menuToggle() { apply(visibility.isRevealed ? .hidden : .shown) }
    @objc private func menuShowAll() { apply(visibility == .showingAll ? .hidden : .showingAll) }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuWelcome() { openWelcome() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Open source at github.com/frizurd/tuck",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11),
                                                      .foregroundColor: NSColor.secondaryLabelColor])
        ])
    }

    // MARK: Auto-hide

    private func scheduleAutoHide(after seconds: Double) {
        hideTimer?.invalidate()
        hideTimer = nil
        guard visibility.isRevealed, preferences.autoHide else { return }
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoHideFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    private func autoHideFired() {
        guard visibility.isRevealed else { return }
        if MenuBarEnvironment.blockers().shouldPostpone {
            scheduleAutoHide(after: AutoHideDelay.retrySeconds)
        } else {
            apply(.hidden, explainIfMisplaced: false)
        }
    }

    // MARK: Scroll gesture

    private func setScrollMonitoring(_ enabled: Bool) {
        scrollMonitors.forEach(NSEvent.removeMonitor)
        scrollMonitors.removeAll()
        guard enabled else { return }
        let handle: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handleScroll(event) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: handle) {
            scrollMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { event in
            handle(event)
            return event
        }) {
            scrollMonitors.append(local)
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard MenuBarEnvironment.pointerIsInMenuBar() else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        if scrollGesture.feed(delta: delta, at: event.timestamp) {
            apply(visibility.isRevealed ? .hidden : .shown)
        }
    }

    // MARK: Always-hidden section

    private func addAlwaysHiddenItem() {
        guard alwaysHiddenItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: dividerWidth)
        item.autosaveName = "tuck.always-hidden"
        configure(item, label: "Tuck always-hidden divider", action: #selector(dividerClicked))
        item.button?.image = Glyphs.alwaysHiddenDivider
        item.button?.toolTip = "Icons left of this line stay hidden until you ⌥-click the chevron."
        alwaysHiddenItem = item
    }

    private func removeAlwaysHiddenItem() {
        guard let item = alwaysHiddenItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        alwaysHiddenItem = nil
    }

    private func observePreferences() {
        preferences.$alwaysHiddenSection
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    addAlwaysHiddenItem()
                    // Reveal everything so the new divider is visible and can be dragged into place.
                    DispatchQueue.main.async { self.apply(.showingAll) }
                } else {
                    removeAlwaysHiddenItem()
                    DispatchQueue.main.async { self.apply(self.visibility == .showingAll ? .shown : self.visibility) }
                }
            }
            .store(in: &subscriptions)

        preferences.$scrollToToggle
            .sink { [weak self] enabled in self?.setScrollMonitoring(enabled) }
            .store(in: &subscriptions)

        Publishers.CombineLatest(preferences.$autoHide, preferences.$autoHideDelay)
            .dropFirst()
            .sink { [weak self] _, delay in self?.scheduleAutoHide(after: delay) }
            .store(in: &subscriptions)
    }

    // MARK: Misplaced divider

    private func explainMisplacedDivider() {
        guard let button = toggleItem.button else { return }
        misplacedPopover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MisplacedDividerView {
            popover.close()
        })
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        misplacedPopover = popover
    }
}

private struct MisplacedDividerView: View {
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("The divider is on the wrong side", systemImage: "arrow.left.and.right")
                .font(.headline)
            Text("Hold ⌘ and drag the thin │ line so it sits to the **left** of the chevron. Tuck hides the icons on the left of that line.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Got It", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
