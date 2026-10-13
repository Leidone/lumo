<p align="center">
  <img src="docs/assets/icon.png" width="128" alt="Lumo icon">
</p>

<h1 align="center">Lumo</h1>

<p align="center">
  A menu bar app that keeps your Mac fast — and replaces a drawer full of little utilities.<br>
  Native, private, free. Turn on only what you use.
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#everything-it-does">Features</a> ·
  <a href="#private-by-default">Privacy</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="SUPPORT.md">Support</a>
</p>

<p align="center">
  <a href="../../releases"><img src="https://img.shields.io/badge/release-1.0.0-4c7dff" alt="Release 1.0.0"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-0b1230" alt="macOS 14 and newer">
  <img src="https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-5e5ce6" alt="Universal binary">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-8e9bff" alt="MIT license"></a>
</p>

<p align="center">
  <img src="docs/assets/overview.png" width="300" alt="The Lumo panel with live CPU, memory and disk rings on a deep navy background">
  <img src="docs/assets/island.png" width="520" alt="The Dynamic Island around the notch, showing the playing track with a scrubber, timers and quick controls">
</p>

Lumo started as a one-click optimizer: it watches CPU, memory and disk, finds what is weighing your Mac down and stops it safely. It grew into a set of everyday tools — a Dynamic Island, window management, clipboard history, screen capture, a per-app volume mixer and more — all behind one menu bar icon. Every tool is off until you switch it on, and each one asks only for the permissions it needs.

## Install

1. Download **Lumo.dmg** from [Releases](../../releases).
2. Open it and drag **Lumo** onto **Applications**.
3. The first time only: Lumo is not signed with a paid Apple Developer ID, so macOS stops it once. Open Lumo, click **Done**, then go to **System Settings → Privacy & Security** and click **Open Anyway**. If the button isn't there:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Lumo.app
   ```

Requires macOS 14 Sonoma or later. One universal app for Apple silicon and Intel.

> Because the build is ad-hoc signed, macOS forgets granted permissions after each update. Turn them on again under **Lumo → Tools → Permissions**.

## Everything it does

### Keep the Mac fast
- **One-click optimize.** Finds runaway processes and heavy apps and stops them safely, with a report of what came back.
- **Cleanup intensity dial** and **auto-optimize** when load stays above your threshold.
- **Processes.** The heaviest apps and background processes, with "stop now" and "never touch".
- **Cleaner** for caches, logs, Xcode builds and app leftovers, on demand or weekly. **Uninstaller** that removes apps with their traces.
- **Sensors.** Temperatures, GPU load, power draw in watts, the most energy-hungry apps and fan speed with manual control.
- **Network.** Live traffic, session totals, local IP and Apple's speed test.
- **Menu bar readouts** for CPU, memory, GPU, network, temperature, fan, power and battery — as numbers or bars.
- **Alerts** for sustained CPU load, memory pressure, low disk, low battery and overheating.
- **Updates** from Homebrew, the App Store and apps' own update feeds. **Messenger downloads** from Telegram, WhatsApp, Viber and WeChat with a retention rule.

### Sound
- **Volume mixer.** Volume per app, boost past 100%, a different output per app, favorites in your order.
- **Outputs and microphones.** Switch outputs with a shortcut, lower the volume when headphones disconnect, keep a preferred microphone, set its level and mute every mic at once.
- **Music launch blocker** for the Play key.

### Windows and the Dock
- **Window layout.** Halves, quarters, thirds and more with shortcuts, edge snapping, ⌃⌥-drag to move and ⌃⌥⇧-drag to resize from anywhere.
- **App switcher** for ⌘Tab with live previews, search, one tile per window and a this-display filter.
- **Dock previews** on hover, **Dock clicks** that minimize, hide or cycle windows, a **green button** that fills the screen without a new Space, a **fixed Spaces order** and **quit when the last window closes**.
- **⌘Q / ⌘W protection** by holding or pressing twice.

### Keyboard and mouse
- **Smooth, linear and sideways scrolling**, reversed mouse scrolling, no pointer acceleration.
- **Mouse buttons and side wheels** mapped to actions, **middle-button gestures** for Spaces and Mission Control, **three-finger middle click**.
- **Focus follows mouse**, an **extra click filter** for worn buttons, **key debounce**, a **Super key** on Caps Lock or a right-hand modifier, and per-app exclusions.
- **Shortcuts page** to rebind every Lumo shortcut, with optional takeover of ⌘⇧3/4/5.

### Clipboard, files and links
- **Clipboard history** with search and pins, **auto-clear**, **paste as plain text** and **snippets**.
- **Shelf** for files, text and links — shake the pointer while dragging, or drop onto the notch.
- **Clean links** of tracking parameters, **Finder shortcuts** (⌘X/⌘V move, F2 rename, paste an image as PNG) and a **disk image installer**.

### Everyday tools
- **Dynamic Island** around the notch (or a simulated one): any player's now playing with artwork and scrubbing, optional live equalizer and synced lyrics, timers, calendar with Join buttons, downloads, notifications, a files shelf, notes, AI agents and a camera mirror.
- **Command Bar** (⌥Space): apps, files, windows, menu commands, clipboard, snippets, calculator, units, emoji, your own scripts and every Lumo action.
- **Quick panel** (⌃⌘V) and a **radial menu** with profiles and folders.
- **Notes** in a floating scratchpad, **AI agents** (Claude Code, Codex, OpenCode, Copilot) with plan limits, API value and a finished-task heads-up, and a **cleaning mode** that locks the keyboard.
- **Quick toggles:** Dark Mode, desktop icons, hidden files, eject disks, sleep display, lock, empty Trash.

### Capture
- **Lumo selector** with a mode bar and a pixel loupe: area, window, screen, **scrolling screenshots**, recording, text and color.
- **Screenshot editor** with arrows, boxes, highlighter, redaction, crop, backgrounds, watermark, Share menu and 24-hour links.
- **Screen recording** with separate system audio and microphone tracks; an editor to trim, cut, blur and auto-zoom on clicks; MP4 and GIF.
- **Text and QR from the screen**, a **color picker**, pinned images, a **camera mirror** and **media tools** to compress video, convert images and pull text out of them.

### Energy and displays
- **Stay awake** on a timer, while chosen apps run, while plugged in or with an external display — and with the lid closed.
- **Displays:** brightness for every screen (DDC/CI for external monitors), ½ and ¼ steps for the brightness keys, dimming below the minimum and XDR extra brightness on displays that have the headroom.
- **Bluetooth off during sleep**, back on at wake.

### Install only what you use
Remove any feature on the **Features** page — it stops running and leaves the panel; adding it back restores its settings. Pick a preset, reorder sections, use a compact grid, and export your settings to another Mac. The **Permissions** page shows what each permission is for, which of your features use it, and when one is no longer needed.

## Private by default

No account, no analytics, no tracking. Lumo works on your Mac; the network is used only for things you can see — update checks, the speed test, Homebrew, opt-in lyrics, opt-in Claude limits and 24-hour links you create. Details: [Privacy](docs/PRIVACY.md) · [Permissions](docs/PERMISSIONS.md).

## Safety model

Lumo only stops processes it can prove are yours and third-party. System processes, other users' and root processes, anything started from Terminal, the app in front of you and anything you shield are never touched. Apps are asked to quit like ⌘Q so you can save; background processes get `SIGTERM`, and `SIGKILL` only at intensity 80% and above.

**Passwordless purge.** `purge` needs root. With **Settings → No password**, macOS asks for your admin password once and Lumo installs `/etc/sudoers.d/lumo`, allowing exactly three commands and nothing else:

```
<you> ALL=(root) NOPASSWD: /usr/sbin/purge, /usr/bin/dscacheutil -flushcache, /usr/bin/killall -HUP mDNSResponder
```

The rule is validated with `visudo` and activated atomically. Fan speed and lid-closed mode use macOS's own administrator prompt each time and keep no lasting privileges.

## Build it yourself

Xcode 16 or newer (Swift 6 toolchain).

```bash
git clone https://github.com/Leidone/lumo.git
cd lumo
swift test                 # the core logic test suite
./scripts/build_dmg.sh     # → build/Lumo.app and build/Lumo.dmg
```

The script runs the tests, builds a universal release binary and the two small helpers (`Helpers/`), renders the icon, ad-hoc signs the app and packs the DMG with `Install Instructions.txt`. See [Contributing](CONTRIBUTING.md) for the layout and conventions.

## When something misbehaves

[Troubleshooting](docs/TROUBLESHOOTING.md) covers launch problems, permissions and missing features. Otherwise see [Support](SUPPORT.md); security issues go through [Security](SECURITY.md).

## License

[MIT](LICENSE) © 2026 [Leidone](https://github.com/Leidone). The license covers the source code; the Lumo name and icon are covered by [TRADEMARKS.md](TRADEMARKS.md). Third-party services and system frameworks are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

### По-русски

Lumo — приложение в строке меню, которое держит Mac быстрым и заменяет десяток мелких утилит: оптимизатор и очистка, датчики и сеть, микшер громкости, Dynamic Island, управление окнами и Dock, история буфера, захват и запись экрана, Command Bar, яркость мониторов и многое другое. Всё выключено, пока вы сами не включите; каждая функция просит только нужные ей разрешения. Интерфейс на русском и английском.

**Установка:** скачайте `Lumo.dmg` из [Releases](../../releases), перетащите Lumo в «Программы», при первом запуске нажмите «Всё равно открыть» в «Системные настройки → Конфиденциальность и безопасность».
