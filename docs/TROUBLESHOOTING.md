# Troubleshooting

### "Apple could not verify Lumo is free of malware"
Expected for apps outside the App Store without a paid Developer ID. Open Lumo once, click **Done**, then **System Settings → Privacy & Security → Open Anyway**. Or run `xattr -dr com.apple.quarantine /Applications/Lumo.app`.

### I granted a permission but the feature still doesn't work
Lumo picks up permissions within a couple of seconds. If nothing happens — usually right after an update — remove Lumo from that list in **System Settings → Privacy & Security** (the **−** button), then add it back or press **Allow** on Lumo's Permissions page. Make sure the copy in /Applications is the one you granted.

### Shortcuts don't fire
Check **Tools → Shortcuts** for the current binding and that the feature itself is on. Another app may own the same combination; record a new one. Window shortcuts, the Command Bar and the clipboard panel need no permission; most mouse and keyboard tools need Accessibility.

### ⌘Tab shows the macOS switcher
Lumo's switcher needs **Replace ⌘Tab** and Accessibility. If Lumo quits unexpectedly, macOS's ⌘Tab comes back the next time Lumo starts or after logging out.

### Caps Lock stopped working
That's the Super key on Caps Lock. Set **Tools → Keyboard → Super key** to Off, or quit Lumo; a restart also restores Caps Lock.

### The Dynamic Island doesn't show music
Now playing works with any app that reports to macOS (Music, Spotify, browsers, podcasts). If nothing shows, start playback again. When the system bridge is unavailable Lumo falls back to Music and Spotify, which needs the one-time Automation prompt.

### Notifications don't appear in the island
They need the Notifications section turned on (Island settings) and **Full Disk Access** for Lumo.

### Lumo uses more CPU than expected
Idle use is about 0.1%. Open features (the panel, a sensors page, an expanded island) cost a little while visible. If CPU stays high with everything closed, note what was playing or open and [file an issue](../SUPPORT.md).

### The Mac sleeps even though a rule should keep it awake
Rules are checked every two seconds; a timer from the Overview tab also works. Lid-closed mode is separate: turn it on under **Tools → Stay awake** (macOS asks for the admin password).

### External monitor brightness doesn't change
DDC/CI must be supported and enabled in the monitor's own menu; some USB-C hubs and docks block it. Without DDC, Lumo dims the picture in software instead.

### Fans
Fan control appears only on Macs with fans. Every change asks for the administrator password and can be returned to **Auto** at any time.

### Removing Lumo completely
See [Privacy → Removing everything](PRIVACY.md#removing-everything).
