# Contributing to Lumo

Thanks for helping! Bug reports, ideas, translations and pull requests are all welcome.

## Build and test

Requirements: macOS 14 or later, Xcode 16 or newer (Swift 6 toolchain). No other dependencies.

```bash
swift build                # debug build
swift test                 # the LumoCore test suite (Swift Testing)
./scripts/build_dmg.sh     # tests + universal release build + helpers + DMG
```

Run a debug build with `swift run Lumo`. To try features that need permissions (Accessibility, Screen Recording), build the DMG, install it to /Applications and grant them there — permissions are tied to the app's location and signature.

## Layout

```
Sources/LumoCore/        Pure, tested logic: process classification, planning, parsers
                         (ps, lsof, brew, appcasts, agent logs, LRC lyrics), calculator,
                         URL cleaner, scroll stitching, edit ranges, fan curves…
Sources/Lumo/
  System/                Sampling (mach, sysctl, IOKit), optimizer, maintenance, admin prompts
  Features/              One file (or folder) per tool: Island/, CaptureSelector, DockTools,
                         MouseTools, KeyboardTools, AudioDevices, FeatureHub, PermissionCenter…
  MenuBar/               Status item, Core Animation icon, readouts
  UI/                    Design system (navy theme, cards, glass), tabs, pages per category
Helpers/                 NowPlaying.m (MediaRemote bridge), FanHelper.c (validated SMC writes)
Tests/LumoCoreTests/     Swift Testing suites
scripts/                 DMG build script and icon renderer
```

## Conventions

- **Logic that can be tested goes into `LumoCore`** with tests (`Tests/LumoCoreTests`). App code stays thin.
- **Every feature is off by default** and asks only for the permission it needs. Add it to `FeatureCatalog`, `FeatureHub` (its background switches) and `PermissionCenter` (which permission it uses).
- **Idle cost matters.** Lumo idles around 0.1% CPU. Don't add timers that run while nothing is visible; animate with Core Animation rather than SwiftUI timelines; pause work while the popover is closed.
- **No new network calls** without a visible, user-initiated reason, and document them in [PRIVACY](docs/PRIVACY.md) and [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md).
- **No root by default.** Anything privileged goes through macOS's administrator prompt or the narrow sudoers rule; never widen that rule.
- **Both languages.** Every user-facing string uses `t("Русский", "English")`.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, `docs:`…).
- Don't copy code or assets from projects under incompatible licenses.

## Pull requests

Keep them focused, describe what changed and how you tested it, and make sure `swift test` passes. The PR template has a short checklist. By contributing you agree that your work is released under the [MIT License](LICENSE). AI-assisted changes are fine — see [AI contributions](docs/AI-CONTRIBUTIONS.md).
