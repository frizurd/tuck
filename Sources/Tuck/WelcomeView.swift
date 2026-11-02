import SwiftUI

struct WelcomeView: View {
    var finish: (_ openAtLogin: Bool) -> Void
    @State private var openAtLogin = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("Welcome to Tuck")
                    .font(.system(size: 22, weight: .semibold))
                Text("A tidy menu bar. The icons you rarely need stay out of sight.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)

            MenuBarDemo()
                .padding(.top, 22)
                .padding(.bottom, 38)

            VStack(alignment: .leading, spacing: 14) {
                Step(symbol: "command", title: "Hold ⌘ and drag icons left of the │ divider",
                     detail: "Anything on the left of the divider gets tucked away.")
                Step(symbol: "chevron.left", title: "Click the chevron to bring them back",
                     detail: "Or scroll on the menu bar, or press your own shortcut.")
                Step(symbol: "timer", title: "They tuck themselves away again",
                     detail: "After 10 seconds, but never while you're using one.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)

            HStack {
                Toggle("Open Tuck at login", isOn: $openAtLogin)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Get Started") { finish(openAtLogin) }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(.bar)
            .padding(.top, 24)
        }
        .frame(width: 520)
    }
}

private struct Step: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A looping miniature of the menu bar: drag an icon across the divider, then tuck.
private struct MenuBarDemo: View {
    private struct Icon: Identifiable, Equatable {
        let id: String
        var symbol: String { id }
    }

    private let start = (hidden: [Icon(id: "cloud"), Icon(id: "paperplane")],
                         shown: [Icon(id: "music.note"), Icon(id: "bolt.fill"), Icon(id: "wifi")])

    @State private var hidden: [Icon] = []
    @State private var shown: [Icon] = []
    @State private var collapsed = false
    @State private var dragging = false
    @Namespace private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "apple.logo").font(.system(size: 13))
            Text("Finder").font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 8)
            if !collapsed {
                ForEach(hidden) { icon in iconView(icon) }
                Capsule().frame(width: 1.5, height: 13).opacity(0.5)
                    .transition(.opacity)
            }
            Image(systemName: collapsed ? "chevron.left" : "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
            ForEach(shown) { icon in iconView(icon) }
            Text("Mon 9:41").font(.system(size: 12, weight: .medium)).monospacedDigit()
        }
        .padding(.horizontal, 14)
        .frame(width: 440, height: 30)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.quaternary))
        .overlay(alignment: .bottom) {
            if dragging {
                Text("⌘ drag")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
                    .offset(y: 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animation: an icon is dragged left of the divider, then hidden.")
        .task { await loop() }
    }

    private func iconView(_ icon: Icon) -> some View {
        Image(systemName: icon.symbol)
            .font(.system(size: 13))
            .frame(width: 16)
            .matchedGeometryEffect(id: icon.id, in: space)
            .transition(.opacity.combined(with: .scale(scale: 0.6)))
    }

    private func loop() async {
        hidden = start.hidden
        shown = start.shown
        guard !reduceMotion else { return }
        let spring = Animation.spring(response: 0.5, dampingFraction: 0.82)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(spring) { dragging = true }
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(spring) {
                let moved = shown.removeFirst()
                hidden.append(moved)
            }
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(spring) { dragging = false }
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(spring) { collapsed = true }
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(spring) { collapsed = false }
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(spring) {
                hidden = start.hidden
                shown = start.shown
            }
        }
    }
}
