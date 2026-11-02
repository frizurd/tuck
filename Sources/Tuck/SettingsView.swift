import Combine
import ServiceManagement
import SwiftUI
import TuckCore

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    var showWelcome: () -> Void

    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var menusReadable = AppMenus.isTrusted
    private let trustCheck = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Open Tuck at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, enabled in setLoginItem(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                } else if LoginItem.needsApproval {
                    HStack {
                        Text("Waiting for approval in System Settings.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                            .controlSize(.small)
                    }
                }
            }

            Section {
                Toggle("Hide icons again automatically", isOn: $preferences.autoHide)
                LabeledContent("After") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(get: { preferences.autoHideDelay },
                                              set: { preferences.autoHideDelay = $0.rounded() }),
                               in: AutoHideDelay.range)
                            .frame(width: 160)
                        Text("\(Int(preferences.autoHideDelay)) sec")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                .disabled(!preferences.autoHide)
                Toggle("Scroll on the menu bar to show or hide", isOn: $preferences.scrollToToggle)
                if !(menusReadable && NativeHider.isSupported) {
                    Toggle("Show the divider line", isOn: $preferences.showDivider)
                }
            } header: {
                Text("Hiding")
            } footer: {
                Text("Tuck waits while your pointer is in the menu bar or a menu is open. Turn the divider line on while you arrange icons, or ⌃-click the chevron.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                LabeledContent {
                    if menusReadable {
                        Label("On", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Allow Access…") { AppMenus.requestAccess() }
                    }
                } label: {
                    Text("Hide icons cleanly")
                }
            } footer: {
                Text(menusReadable
                     ? (NativeHider.isSupported
                        ? "macOS hides the icons left of the chevron itself. No divider and no « marker."
                        : "Tuck reads where the app menus end so hidden icons leave no trace.")
                     : "Without Accessibility access, macOS shows a « next to the chevron while icons are hidden. Tuck only reads which app owns each menu bar icon and where the app menus end.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                Toggle("Add an always-hidden section", isOn: $preferences.alwaysHiddenSection)
            } header: {
                Text("Always Hidden")
            } footer: {
                Text("A dotted ┆ divider appears. Icons left of it stay hidden until you ⌥-click the chevron.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                LabeledContent("Show or hide icons") {
                    ShortcutRecorder(shortcut: $preferences.shortcut)
                }
                if preferences.shortcutConflict {
                    Text("Another app already uses this shortcut. Try a different one.")
                        .font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Keyboard")
            } footer: {
                Text("Also scriptable: open tuck://toggle, tuck://show, tuck://show-all or tuck://hide.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                HStack {
                    Text("Tuck \(Self.version)").foregroundStyle(.secondary)
                    Spacer()
                    Button("How to Use Tuck", action: showWelcome)
                    Link("GitHub", destination: URL(string: "https://github.com/frizurd/tuck")!)
                        .padding(.leading, 6)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(trustCheck) { _ in menusReadable = AppMenus.isTrusted }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            openAtLogin = LoginItem.isEnabled || LoginItem.needsApproval
        }
    }

    private func setLoginItem(_ enabled: Bool) {
        let current = LoginItem.isEnabled || LoginItem.needsApproval
        guard enabled != current else { loginError = nil; return }
        do {
            try LoginItem.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
            openAtLogin = current
        }
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
