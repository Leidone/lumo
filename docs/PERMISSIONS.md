# Permissions

Every permission is optional. Lumo asks for one only when you turn on a feature that needs it, and **Tools → Permissions** shows each permission's status, the features using it and a warning when nothing needs it anymore.

| Permission | Features that use it | Without it |
|---|---|---|
| **Accessibility** | Window layout, app switcher, Dock tools, ⌘Q/⌘W protection, mouse and keyboard tools, Super key, clipboard paste, snippets, Finder shortcuts, Music blocker, brightness keys, cleaning mode, Command Bar menu commands | Those features stay off; everything else works |
| **Screen & System Audio Recording** | Lumo selector, scrolling screenshots, screen recording, window previews (switcher, Dock), volume mixer, live equalizer | macOS's own screenshot tool is used; previews show icons; the mixer and live equalizer are unavailable |
| **Microphone** | The microphone track in recordings | Recordings have system audio only |
| **Camera** | Camera mirror (island and floating) | No camera preview |
| **Calendars** | Meetings in the Dynamic Island | No calendar section |
| **Full Disk Access** | Notifications in the Dynamic Island | No notifications section |
| **Notifications** | Alerts, finished AI tasks, the scheduled cleaner | Silent |
| **Bluetooth** | Bluetooth off during sleep | Bluetooth stays as it is |
| **Automation** (per app) | Dark Mode toggle (System Events), empty Trash and paste-image-as-PNG (Finder), Music/Spotify fallback | Those actions don't run |
| **Downloads folder** | Download progress in the Dynamic Island | No downloads section |
| **Keychain item "Claude Code-credentials"** | Claude plan limits (off by default) | Limits for Claude aren't shown; token counts still are |

**Administrator password** is never stored. macOS asks for it when you enable the passwordless purge rule, change a fan speed or switch lid-closed mode.

**After an update** of an ad-hoc signed build, macOS treats Lumo as a new app and drops Accessibility and Screen Recording. Remove Lumo from those lists in System Settings and add it again, or use the buttons on the Permissions page.
