# Changelog

All notable changes to Lumo are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.1] — 2026-10-29

### Summary
A battery release. Lumo no longer keeps audio running in the background and wakes the Mac less often, especially on battery.

### Fixed
- The volume mixer kept a per-app audio tap running for as long as the app existed, even in silence, so the output device and Bluetooth headphones could never idle. Taps now start when the app plays and stop five seconds after it goes quiet; playback changes are pushed by CoreAudio instead of polled.
- The island's live equalizer listened to system audio whenever a player claimed to be playing. It now runs only while sound actually plays and the screens are awake, and its level updates pause while the island is hidden.

### Changed
- Background sampling adapts: every 2 s while Lumo's panel, sensors or the expanded island are open, 3 s otherwise, 6 s on battery and 10 s in Low Power Mode.
- The menu bar icon's shimmer and pulse pause on battery and in Low Power Mode.
- Pointer movement far from the notch is ignored without any work, the clipboard is checked once a second, and every repeating timer allows the system to coalesce wakeups.

## [1.0.0] — 2026-10-13

### Summary
The first public release. Lumo keeps your Mac fast from the menu bar and bundles the everyday utilities Mac users usually collect one by one — a Dynamic Island, window and Dock tools, clipboard history, screen capture, a volume mixer and more — in one native, private app. Every tool is off until you turn it on.

### Keep the Mac fast
- One-click optimize with a safe process classifier, a cleanup intensity dial and auto-optimize above a threshold you choose (10–100%).
- Processes tab with "stop now" and "never touch", cleaner for caches, logs, Xcode builds and leftovers (on demand or weekly), and an uninstaller that removes app traces.
- Sensors with temperatures, GPU load, power draw, energy-hungry apps and manual fan speed; network traffic, session totals and Apple's speed test.
- Menu bar readouts as numbers or bars; alerts for CPU, memory pressure, disk, battery and overheating.
- Updates from Homebrew, the App Store and apps' own Sparkle feeds; messenger download cleanup with a retention rule.

### Dynamic Island
- Lives around the notch and stays exactly notch-sized when idle, so the menu bar beside it remains clickable; a simulated island on Macs without a notch.
- Now playing from any player — browsers included — with artwork, a tinted glow, scrubbing, an optional live equalizer and synced lyrics.
- Timers, calendar with Join buttons and a five-minute heads-up, downloads, notifications, a files shelf you can drop onto, notes, AI agent limits and a camera mirror.

### Sound
- Per-app volume with boost and per-app outputs, favorites in your order.
- Output switching by shortcut, quieter speakers when headphones disconnect, a preferred microphone with its level, mute every microphone at once, and a Music launch blocker.

### Windows, keyboard and mouse
- Window layout by shortcut, edge snapping and modifier-drag; ⌘Tab switcher with previews, search and per-window mode; Dock previews and click actions; green-button maximize; fixed Spaces order; quit on last window close; ⌘Q/⌘W protection.
- Smooth, linear and sideways scrolling, button and side-wheel mapping, middle-button gestures, three-finger middle click, focus follows mouse, click and key debounce, a Super key and per-app exclusions.
- A Shortcuts page that rebinds every Lumo shortcut, with optional takeover of ⌘⇧3/4/5.

### Clipboard, files and links
- Clipboard history, auto-clear, paste as plain text and snippets.
- The Shelf, tracking-free links, Finder shortcuts and a disk image installer.

### Everyday tools
- Command Bar with windows, menu commands and your own scripts; Quick panel; radial menu with profiles and folders.
- Floating scratchpad, AI agents with plan limits and API value, cleaning mode and quick toggles.

### Capture
- Lumo selector with a mode bar, pixel loupe and scrolling screenshots.
- Screenshot editor with crop, backgrounds, watermark, Share menu and 24-hour links.
- Screen recording with separate audio tracks and an editor to trim, cut, blur and auto-zoom; MP4 and GIF; media tools for video and images.

### Energy and displays
- Stay awake by timer, app, power or external display, and with the lid closed.
- Brightness for every display (DDC/CI for external monitors), finer brightness-key steps, dimming below the minimum, XDR extra brightness and Bluetooth off during sleep.

### App
- Features page to remove or restore any tool with its settings, presets, section order, compact grid and settings export.
- Permissions page explaining every permission and flagging the ones no longer needed.
- A deep navy design with Liquid Glass on macOS 26, English and Russian interface, about 0.1% CPU when idle.

[1.0.1]: https://github.com/Leidone/lumo/releases/tag/v1.0.1
[1.0.0]: https://github.com/Leidone/lumo/releases/tag/v1.0.0
