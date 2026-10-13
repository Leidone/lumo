# Third-party notices

Lumo has **no third-party code dependencies**: `Package.swift` declares no packages, and every source file in this repository was written for Lumo. The app links only frameworks that ship with macOS.

## Prior art

Lumo's feature set was inspired by [vorssaint-utils](https://github.com/vorssaint/vorssaint-utils) (GPL-3.0-or-later). No code, assets, text or visual design from that project were copied; Lumo's implementation, interface and branding are its own. Thanks to its maintainer for showing what a single menu bar utility can do.

## Apple frameworks

Lumo uses public Apple frameworks (AppKit, SwiftUI, Core Audio, ScreenCaptureKit, AVFoundation, Vision, EventKit, IOKit and others) under the terms of the macOS SDK.

Some features call private macOS frameworks that have no public equivalent. They are loaded at run time and fail gracefully if unavailable:

| Framework | Used for |
|---|---|
| MediaRemote | Now playing in the Dynamic Island (through a small bridge in `Helpers/NowPlaying.m`) |
| MultitouchSupport | Counting fingers for the three-finger middle click |
| DisplayServices | Built-in display brightness |
| IOKit `IOAVService` | DDC/CI brightness for external monitors |
| CoreGraphics `CGSSetSymbolicHotKeyEnabled` | Replacing ⌘Tab and taking over ⌘⇧3/4/5 |
| IOBluetooth preferences | Bluetooth off during sleep |
| login `SACLockScreenImmediate` | Locking the screen |
| IOHIDEventSystem | Temperature sensors and live pointer-acceleration changes |

## Online services

These are contacted only when you use the related feature:

| Service | When | What is sent |
|---|---|---|
| [lrclib.net](https://lrclib.net) | Lyrics turned on in the Dynamic Island | Track title, artist, album and duration |
| [litterbox.catbox.moe](https://litterbox.catbox.moe) | You choose "24-hour link" (asked once) | The file you share |
| api.anthropic.com | Claude plan limits turned on | Your Claude Code sign-in token, read from your Keychain for that request |
| Apple `networkQuality` servers | You run the speed test | Test traffic |
| Developers' update feeds (SUFeedURL) | You check for app updates | A request for each app's public feed |
| Homebrew and the App Store | You use the Updates page | What `brew` and `mas` normally send |

Each service has its own terms; Lumo is not affiliated with any of them.
