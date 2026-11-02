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

Tuck adds a chevron `‹` and a thin divider `│` to your menu bar. The divider line only shows while you set things up. ⌃-click the chevron to show it again when you want to rearrange.

- **Hold ⌘ and drag icons to the left of the divider.** Those are the hidden ones.
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

The divider is an ordinary status item. To hide icons, Tuck makes it very wide so the icons to its left no longer fit in the menu bar.

Before macOS 26, apps made the divider 10,000 points wide and the extra icons just ran off the screen. macOS 26 and later lay the menu bar out differently. A status item that would run into the app menus gets ignored completely, which is why Hidden Bar stopped working.

From testing on macOS 27, two rules decide what happens:

- A status item longer than about half the screen is ignored.
- Icons that no longer fit go into the system overflow, and macOS draws a `«` in any free space left of the divider. If the divider reaches all the way to the app menus, there's no free space, and the icons are dropped quietly with no `«`.

So when Tuck can read where the front app's menus end, and reaching them stays under half the screen, it stretches the divider right up to them. That needs Accessibility access, which Tuck asks for in Settings under **Hide without the « marker**. It reads only the menu width, and it measures again whenever you switch apps.

Otherwise Tuck aims the divider's edge at the middle of the notch. That always hides your icons, but macOS shows its `«` next to the chevron. This happens in apps with short menus (Finder, for example) when the chevron sits far to the right, because reaching those menus would take more than half the screen. The more icons you keep to the right of the chevron, the further left it sits, and the more apps hide cleanly. On macOS 14 and 15, Tuck uses the old 10,000-point trick.

Right after you switch apps, Tuck briefly uses the notch method until it has measured the new menus. A divider sized for shorter menus would run into longer ones and be ignored, and your hidden icons would flash back.

The divider's line only shows while you're arranging icons: during setup, or after you ⌃-click the chevron or turn it on in Settings. It stays blank while the divider is stretched or resizing, so it never slides across the menu bar.

Apart from the optional Accessibility access, Tuck needs no permissions, and it makes no network requests. The shortcut uses the Carbon hot key API, which doesn't need any permission. Open at login uses `SMAppService`.

The decisions live in `Sources/TuckCore` as plain functions with tests: which divider width to use, when the divider position is valid, when auto-hide should wait, and how shortcuts and URLs are parsed.

```sh
swift test
```

## Things I haven't nailed yet

- macOS shows its `«` overflow marker next to the chevron while icons are hidden, unless Tuck can reach the front app's menus (see above).
- I've tested on a 14" MacBook Pro with a notch, running macOS 27. Without Accessibility access on a display with no notch, Tuck assumes the app menus use less than half the menu bar, so with very long menus a hidden icon could peek out. Reports from external-display setups are welcome.
- Status items appear on every display, but Tuck measures from the display its own chevron is on.

## Credits

Inspired by [Hidden Bar](https://github.com/dwarvesf/hidden) by Dwarves Foundation (MIT). Tuck is a new codebase.

## License

MIT
