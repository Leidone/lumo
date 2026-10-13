# Privacy

Lumo is local-first. There is no account, no analytics, no crash reporter and no tracking of any kind.

## What stays on your Mac

- **Clipboard history** (`~/Library/Application Support/Lumo/Clipboard`). Copies marked as concealed or transient — what password managers use — are never recorded. Clearing the history deletes the files.
- **Notes, snippets, shelf items, radial menu and every setting** live in Lumo's preferences on this Mac. *Export settings* writes them to a file only when you ask.
- **Screenshots and recordings** are saved where you choose (recordings in `~/Movies/Lumo`).
- **AI agent usage** is read from the agents' own local logs (`~/.claude`, `~/.codex`, OpenCode and Copilot folders). Only token counts, model names, project folder names and times are read — never message text.
- **Notifications** in the Dynamic Island are read from macOS's notification database on your Mac, only if you enable that section and grant Full Disk Access.
- **Calendar events**, **camera** and **microphone** are used on the Mac only, for the features that show them.

## When Lumo uses the network

Only for something you can see or turned on:

| Feature | Destination | What is sent |
|---|---|---|
| Lyrics (off by default) | lrclib.net | Title, artist, album and duration of the playing track |
| 24-hour link (asked once) | litterbox.catbox.moe | The screenshot or recording you share; anyone with the link can open it until it expires |
| Claude plan limits (off by default) | api.anthropic.com | Your Claude Code sign-in token, read from the Keychain for that one request and never stored by Lumo |
| Speed test | Apple's `networkQuality` servers | Test traffic |
| App updates | Each app's own update feed | A request for the public feed |
| Updates page | Homebrew, the App Store | What `brew` and `mas` normally send |
| Command Bar scripts | Wherever your script goes | Whatever your script does |

Nothing else leaves your Mac.

## Removing everything

Quit Lumo, move it to the Trash, then remove `~/Library/Application Support/Lumo`, `~/Library/Preferences/app.lumo.optimizer.plist` and, if you enabled the passwordless option, `/etc/sudoers.d/lumo` (or turn the option off first). If you used the Super key on Caps Lock, Lumo restores Caps Lock when it quits; a restart also clears it.
