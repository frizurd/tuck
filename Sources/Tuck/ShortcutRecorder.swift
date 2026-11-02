import AppKit
import SwiftUI
import TuckCore

/// Click, then press a key combination. ⎋ cancels, ⌫ clears.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @State private var recording = false
    @State private var monitor: Any?
    @State private var rejected = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { recording ? stop() : start() }) {
                Text(title)
                    .font(recording || shortcut == nil ? .body : .body.monospaced())
                    .foregroundStyle(recording ? Color.accentColor : .primary)
                    .frame(minWidth: 120)
            }
            .offset(x: rejected ? 4 : 0)
            .help(recording ? "Press a combination with ⌘, ⌥ or ⌃. ⎋ cancels, ⌫ clears." : "Click to record a shortcut")

            if shortcut != nil, !recording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private var title: String {
        if recording { return "Type shortcut…" }
        return shortcut?.displayString ?? "Record Shortcut"
    }

    private func start() {
        recording = true
        // Let the old shortcut be re-recorded instead of firing.
        HotKeyCenter.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            // Reassigning publishes, which re-registers the unchanged shortcut.
            shortcut = shortcut
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = UInt32(event.keyCode)
        if flags.isDisjoint(with: [.command, .option, .control, .shift]) {
            if keyCode == 53 { stop(); return }                      // ⎋
            if keyCode == 51 || keyCode == 117 { shortcut = nil; stop(); return } // ⌫ ⌦
        }
        var modifiers: Shortcut.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        let label = Shortcut.label(forKeyCode: keyCode)
            ?? event.charactersIgnoringModifiers?.uppercased()
            ?? "?"
        let candidate = Shortcut(keyCode: keyCode, modifiers: modifiers, keyLabel: label)
        guard candidate.isAcceptable else {
            NSSound.beep()
            withAnimation(.spring(response: 0.15, dampingFraction: 0.2)) { rejected = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation { rejected = false } }
            return
        }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        // Setting the binding registers it through Preferences.
        shortcut = candidate
    }
}
