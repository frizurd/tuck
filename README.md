# Tuck

<img src="Assets/AppIcon.png" width="96" alt="Tuck icon">

Tuck hides the menu bar icons you don't need to see all the time. Hold ⌘, drag them to the left of a thin divider, and they're gone until you click the chevron.

I used [Hidden Bar](https://github.com/dwarvesf/hidden) for years. On macOS 27 it stopped hiding anything, and some parts always felt a bit rough, so I rewrote it from scratch. Tuck does the same thing, with more care in the details.

![Welcome window](docs/welcome.png)

## Install

Build it from source. Prebuilt downloads will go on the [Releases](https://github.com/frizurd/tuck/releases) page once there's a notarized build.

```sh
git clone https://github.com/frizurd/tuck.git
cd tuck
./build.sh
cp -R build/Tuck.app /Applications/
open /Applications/Tuck.app
```

You'll need Xcode 15 or newer. Tuck runs on macOS 14 Sonoma and later, and it has no third-party dependencies.

## Using it

Tuck adds a chevron `‹` to your menu bar. On macOS 27 with Accessibility access, icons to the left of the chevron are the hidden ones. Elsewhere, a thin divider `│` sits next to the chevron instead, and its line only shows while you arrange icons (⌃-click the chevron to show it).

- **Hold ⌘ and drag icons to the left of the chevron** (or of the divider, without Accessibility access). Those are the hidden ones.
- **Click the chevron** to show them, and click it again to hide them.
- **Scroll on the menu bar** to do the same thing without aiming for the chevron.
- **Set a shortcut** in Settings to show or hide them from anywhere.
- **Right-click the chevron** for Settings, the welcome guide, and Quit.

After 10 seconds the icons hide again on their own. Tuck waits while your pointer is in the menu bar or any menu is open, so it won't pull an icon away while you're using it. You can change the delay or turn this off.

If you also want an **always-hidden** section, turn it on in Settings. A dotted `┆` divider appears. Icons to the left of it stay hidden until you ⌥-click the chevron.

If the divider ends up on the wrong side of the chevron, Tuck won't hide anything, because that would hide the chevron as well. It shows a popover telling you how to fix it.

![Settings](docs/settings.png)

## Scripting

Tuck handles a `tuck://` URL scheme, so Shortcuts, Raycast, Alfred, or a shell script can control it:

```sh
open -g tuck://toggle
open -g tuck://show
open -g tuck://show-all   # including the always-hidden section
open -g tuck://hide
open tuck://settings
```

## How it works

**On macOS 27, with Accessibility access,** Tuck doesn't stretch anything. It reads which app owns each menu bar icon and where it sits, then asks macOS to allow only the apps on the visible side. It does that through the menu bar restriction behind macOS's assessment (exam) mode, in the private `MenuBarClientCore` framework. macOS removes the other icons and reflows the bar itself. There's no `«`, no divider, and no gap, and it doesn't matter which app is in front. I picked this up from [Hidden Bar](https://github.com/dwarvesf/hidden), which does the same. Some limits come from macOS:

- Hiding works per app, so an app with two icons hides or shows both.
- macOS's own icons (Wi-Fi, clock, Control Center) always stay visible.
- Only apps installed in `/Applications` can stay visible while others are hidden. An app running from somewhere else, such as `~/Applications` or a build folder, gets hidden along with the rest.
- It's a private API. If a macOS update changes it, Tuck falls back to the method below.

**Otherwise,** Tuck hides icons by stretching a divider so the icons on its left no longer fit. Before macOS 26, apps made it 10,000 points wide and the extra icons ran off screen. On macOS 26 and later, measured on macOS 27:

- A status item longer than about half the screen is ignored, which is why that trick stopped working.
- Icons that no longer fit go into the system overflow, and macOS draws a `«` in any free space left of the divider. If the divider reaches the app menus, there's no free space and no `«`.

So when Tuck can read where the front app's menus end, and reaching them stays under half the screen, it stretches the divider to them. Otherwise it aims the divider at the middle of the notch, which always hides your icons but shows the `«`. On macOS 14 and 15, Tuck uses the old 10,000-point trick. In this mode the divider line only shows while you arrange icons: ⌃-click the chevron to show or hide it.

Apart from the optional Accessibility access, Tuck needs no permissions, and it makes no network requests. The shortcut uses the Carbon hot key API, which doesn't need any permission. Open at login uses `SMAppService`.

The decisions live in `Sources/TuckCore` as plain functions with tests: which divider width to use, when the divider position is valid, when auto-hide should wait, and how shortcuts and URLs are parsed.

```sh
swift test
```

## Things I haven't nailed yet

- Without Accessibility access, or before macOS 27, macOS can show its `«` overflow marker next to the chevron while icons are hidden (see above).
- With native hiding, an app launched while icons are hidden stays hidden until you show and hide again, because Tuck can only see where icons sit while nothing is hidden.
- I've tested on a 14" MacBook Pro with a notch, running macOS 27. Without Accessibility access on a display with no notch, Tuck assumes the app menus use less than half the menu bar, so with very long menus a hidden icon could peek out. Reports from external-display setups are welcome.
- Status items appear on every display, but Tuck measures from the display its own chevron is on.

## Credits

Inspired by [Hidden Bar](https://github.com/dwarvesf/hidden) by Dwarves Foundation (MIT). Tuck is a new codebase, except for the small bridge to `MenuBarClientCore` in `Sources/TuckPrivate`, which is adapted from Hidden Bar's.

## License

MIT
