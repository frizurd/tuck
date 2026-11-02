import AppKit
import Combine
import OSLog
import SwiftUI
import TuckCore

/// Owns Tuck's status items and the hide/show state.
///
/// Layout, right to left: `‹ chevron` · `│ divider` · hidden icons · `┆ always-hidden divider` · always-hidden icons.
/// On macOS 27+ with Accessibility, macOS hides icons itself (`NativeHider`) and the
/// chevron is the boundary. Otherwise hiding stretches a divider (see `PushLength`).
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
    private let native = NativeHider()
    private var dragMonitor: Any?

    /// macOS 27+ with Accessibility: macOS hides icons itself and the chevron is the
    /// boundary, so the divider and all the stretching below aren't used.
    private var usesNative: Bool { native.isUsable }

    /// Width of a visible divider: wide enough to grab while ⌘-dragging.
    private var dividerWidth: CGFloat { showsDividerLine ? 14 : 4 }

    /// The line only matters while arranging icons, so it's off once setup is done.
    /// ⌃-click the chevron to bring it back.
    private var showsDividerLine: Bool { preferences.showDivider || !preferences.hasSeenWelcome }

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
        dividerItem.length = dividerWidth
        dividerItem.button?.image = showsDividerLine ? Glyphs.divider : nil
        dividerItem.button?.toolTip = "Icons left of this line are hidden.\n⌘-drag icons across it to choose."

        if preferences.alwaysHiddenSection { addAlwaysHiddenItem() }
        observePreferences()
        watchForAccessibilityGrant()
        startMenuWatch()
        watchMenuBarDrags()
        // Each app has its own menus, so the divider's ideal width changes with the front app.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in
                guard let self, AppMenus.isTrusted, !usesNative else { return }
                // The new app's menus may be longer than the old ones. A divider sized for the
                // old menus would run into them and be ignored, bringing hidden icons back, so
                // switch to the notch-based width (always valid) until the new menus are measured.
                restretch(readMenus: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.restretch(readMenus: true)
                }
            }
            .store(in: &subscriptions)
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
        if usesNative { return applyNative(target) }
        dividerItem.isVisible = true
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

    // MARK: Native hiding (macOS 27+)

    private func applyNative(_ target: BarState) {
        log.debug("native apply \(String(describing: target), privacy: .public) from \(String(describing: self.visibility), privacy: .public)")
        dividerItem.length = dividerWidth
        dividerItem.isVisible = false
        // The always-hidden divider keeps its slot (its position defines that section),
        // but only shows while everything is revealed, so it can be ⌘-dragged.
        if let alwaysHiddenItem {
            alwaysHiddenItem.length = target == .showingAll ? 14 : 0
            alwaysHiddenItem.button?.image = target == .showingAll ? Glyphs.alwaysHiddenDivider : nil
        }
        visibility = target
        updateToggleAppearance()
        scheduleAutoHide(after: preferences.autoHideDelay)
        guard let chevron = toggleItem.button?.window?.frame.midX else { return }
        let alwaysHidden = alwaysHiddenItem?.button?.window?.frame.midX
        native.apply(target, chevronMidX: chevron, alwaysHiddenMidX: alwaysHidden) { [weak self] succeeded in
            guard let self, !succeeded, visibility == target else { return }
            log.error("native hiding failed; nothing is hidden")
            visibility = .shown
            updateToggleAppearance()
        }
        if target != .hidden { scheduleSectionRead() }
    }

    /// Icons can only be located while nothing is restricted, so read them shortly after
    /// revealing and after every click or drag in the menu bar. Hiding then uses that
    /// reading straight away instead of waiting a second for a fresh one.
    private func scheduleSectionRead() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, usesNative, visibility != .hidden,
                  let chevron = toggleItem.button?.window?.frame.midX else { return }
            native.refreshSections(chevronMidX: chevron, alwaysHiddenMidX: alwaysHiddenItem?.button?.window?.frame.midX)
        }
    }

    private func watchMenuBarDrags() {
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.usesNative, self.visibility != .hidden,
                      MenuBarEnvironment.pointerIsInMenuBar() else { return }
                self.scheduleSectionRead()
            }
        }
    }

    private func apply(lengths: DividerLengths) {
        resize(dividerItem, to: lengths.divider, glyph: Glyphs.divider)
        if let alwaysHiddenItem {
            resize(alwaysHiddenItem, to: lengths.alwaysHiddenDivider, glyph: Glyphs.alwaysHiddenDivider)
        }
    }

    /// macOS animates status items as they resize, so a line drawn in the middle of a
    /// shrinking divider would glide across the menu bar. Draw nothing while the divider
    /// is stretched or settling, then put the line back once it has its normal width.
    private func resize(_ item: NSStatusItem, to stretched: CGFloat?, glyph: NSImage) {
        let length = stretched ?? dividerWidth
        guard item.length != length else { return }
        item.button?.image = nil
        item.length = length
        guard stretched == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak item] in
            guard let self, let item, item.length == length else { return }
            item.button?.image = showsDividerLine ? glyph : nil
        }
    }

    /// The last positions read while every divider had its normal width.
    private var measuredPositions: ItemPositions?

    /// macOS reports a made-up frame for a stretched divider, so positions are only read
    /// while the dividers have their normal width. While stretched, the last good reading is
    /// reused; nothing can be ⌘-dragged in the meantime because the dividers are out of sight.
    private func currentPositions() -> ItemPositions? {
        let natural = dividerItem.length == dividerWidth && (alwaysHiddenItem?.length ?? dividerWidth) == dividerWidth
        guard natural else { return measuredPositions }
        guard let toggle = toggleItem.button?.window?.frame,
              let divider = dividerItem.button?.window?.frame else { return measuredPositions }
        let alwaysHidden = alwaysHiddenItem?.button?.window?.frame
        let positions = ItemPositions(toggle: toggle.minX, divider: divider.minX, dividerMaxX: divider.maxX,
                                      alwaysHiddenDivider: alwaysHidden?.minX, alwaysHiddenDividerMaxX: alwaysHidden?.maxX)
        measuredPositions = positions
        return positions
    }

    /// The width that pushes every icon left of a divider out of the menu bar.
    private func pushLength(dividerMaxX: CGFloat) -> CGFloat {
        pushLength(dividerMaxX: dividerMaxX, appMenusMaxX: AppMenus.maxX())
    }

    private func pushLength(dividerMaxX: CGFloat, appMenusMaxX: CGFloat?) -> CGFloat {
        guard let screen = toggleItem.button?.window?.screen ?? NSScreen.main else { return legacyPushLength }
        let legacy = !ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
        let length = PushLength.compute(dividerMaxX: dividerMaxX, screen: screen.frame,
                                        notchLeftArea: screen.auxiliaryTopLeftArea,
                                        notchRightArea: screen.auxiliaryTopRightArea,
                                        appMenusMaxX: appMenusMaxX, legacy: legacy)
        log.debug("push dividerMaxX \(dividerMaxX, privacy: .public) menus \(String(describing: appMenusMaxX), privacy: .public) length \(length, privacy: .public)")
        return length
    }

    /// Granting access happens in System Settings, so check back until it arrives.
    private func watchForAccessibilityGrant() {
        guard !AppMenus.isTrusted else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] timer in
            guard AppMenus.isTrusted else { return }
            timer.invalidate()
            MainActor.assumeIsolated {
                guard let self else { return }
                // Switch to native hiding if this macOS supports it, else re-measure the menus.
                if self.usesNative { self.apply(self.visibility, explainIfMisplaced: false) } else { self.restretch(readMenus: true) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Re-sizes stretched dividers in place, without changing state or the auto-hide timer.
    private func restretch(readMenus: Bool) {
        guard visibility != .showingAll, let positions = currentPositions(), positions.dividerIsUsable else { return }
        let menus = readMenus ? AppMenus.maxX() : nil
        apply(lengths: DividerLengths.resolve(visibility, positions: positions) {
            pushLength(dividerMaxX: $0, appMenusMaxX: menus)
        })
    }

    /// Apps can change their menus without being switched away from, so while a divider is
    /// stretched to the menus' edge, keep checking that edge.
    private func startMenuWatch() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AppMenus.isTrusted, !self.usesNative, self.visibility != .showingAll else { return }
                let natural = self.dividerWidth
                let stretched = self.dividerItem.length != natural
                    || (self.alwaysHiddenItem.map { $0.length != natural } ?? false)
                if stretched { self.restretch(readMenus: true) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: Clicks

    /// Showing the line also shows the icons, since the point is to rearrange them.
    private func toggleDividerLine() {
        preferences.showDivider.toggle()
        if preferences.showDivider, !visibility.isRevealed { apply(.shown) }
    }

    private func dividerLineChanged() {
        apply(visibility, explainIfMisplaced: false)
        for (item, glyph) in [(dividerItem, Glyphs.divider), (alwaysHiddenItem, Glyphs.alwaysHiddenDivider)] {
            guard let item, item.length == dividerWidth else { continue }
            item.button?.image = showsDividerLine ? glyph : nil
        }
    }

    @objc private func toggleClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu(from: toggleItem)
        } else if event.modifierFlags.contains(.control), !usesNative {
            toggleDividerLine()
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
                ? "Click to show hidden icons\n⌥-click to show everything\n⌃-click to show the divider line\nRight-click for options"
                : "Click to show hidden icons\n⌃-click to show the divider line\nRight-click for options"
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
        if !usesNative {
            let line = menuItem("Show Divider Line", #selector(menuDividerLine), key: "")
            line.state = preferences.showDivider ? .on : .off
            line.toolTip = "Shortcut: ⌃-click the chevron"
            menu.addItem(line)
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
    @objc private func menuDividerLine() { toggleDividerLine() }
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
        item.button?.image = showsDividerLine ? Glyphs.alwaysHiddenDivider : nil
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

        Publishers.CombineLatest(preferences.$showDivider, preferences.$hasSeenWelcome)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.dividerLineChanged() }
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
