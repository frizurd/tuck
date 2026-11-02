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

Tuck adds two things to your menu bar: a chevron `‹` and a thin divider `│`.

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

Before macOS 26, apps made the divider 10,000 points wide and the extra icons just ran off the screen. macOS 26 and later lay the menu bar out differently. A status item that would run into the app menus gets ignored completely, which is why Hidden Bar stopped working. A status item that can't be placed for another reason goes into the system overflow (the `«` in the menu bar), and every icon to its left goes with it.

So on a MacBook with a notch, Tuck stretches the divider just far enough that its left edge would land in the middle of the notch. Nothing can be placed there, and the divider never reaches the app menus, so it works no matter which app is in front. Your hidden icons end up in the system `«` overflow, and clicking the chevron brings them back. On macOS 14 and 15, Tuck uses the old 10,000-point trick.

Tuck doesn't need Accessibility or Screen Recording permission, and it makes no network requests. The shortcut uses the Carbon hot key API, which doesn't need any permission. Open at login uses `SMAppService`.

The decisions live in `Sources/TuckCore` as plain functions with tests: which divider width to use, when the divider position is valid, when auto-hide should wait, and how shortcuts and URLs are parsed.

```sh
swift test
```

## Things I haven't nailed yet

- On macOS 26+ the system `«` shows up next to the chevron while icons are hidden. That's macOS showing its overflow, and Tuck can't remove it.
- I've tested on a 14" MacBook Pro with a notch, running macOS 27. On displays without a notch, Tuck can't measure the app menus without Accessibility access. It assumes they use less than half the menu bar, so with very long menus a hidden icon could peek out. Reports from external-display setups are welcome.
- Status items appear on every display, but Tuck measures from the display its own chevron is on.

## Credits

Inspired by [Hidden Bar](https://github.com/dwarvesf/hidden) by Dwarves Foundation (MIT). Tuck is a new codebase.

## License

MIT
