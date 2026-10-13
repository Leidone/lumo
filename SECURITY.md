# Security policy

## Supported versions

Only the latest release receives security fixes.

| Version | Supported |
|---|---|
| 1.0.x | Yes |

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Use GitHub's private vulnerability reporting instead: open the repository's **Security** tab and choose **Report a vulnerability**.

Include what you found, the steps to reproduce it, the macOS version and the Lumo version (Settings → About). You will get an acknowledgement within a few days and a fix or a plan as soon as the issue is understood. Credit is given in the changelog unless you prefer otherwise.

## Areas that matter most

Lumo runs with permissions people trust it with. Reports about these are especially welcome:

- The passwordless rule in `/etc/sudoers.d/lumo` (it must allow exactly three commands) and the administrator prompts used for fan speed and lid-closed mode.
- The bundled helpers in `Helpers/` (the fan helper validates its arguments; the now playing bridge runs inside `/usr/bin/perl`).
- The event tap and anything that could leak keystrokes, clipboard contents or screen captures.
- Reading the Claude Code sign-in from the Keychain for the opt-in plan-limit check.
- Anything that sends data off the Mac (see [Privacy](docs/PRIVACY.md)).
