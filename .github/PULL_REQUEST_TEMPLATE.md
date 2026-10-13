## What and why

<!-- What does this change, and what problem does it solve? Link the issue if there is one. -->

## How I tested it

<!-- macOS version, Mac model, steps you tried, permissions granted. -->

## Checklist

- [ ] `swift test` passes
- [ ] Tried in a real build (`./scripts/build_dmg.sh`) where the change needs permissions
- [ ] New features are off by default and ask only for the permission they need
- [ ] No new background work while nothing is visible (idle CPU stays ~0.1%)
- [ ] User-facing text in both Russian and English
- [ ] No code or assets copied from projects with incompatible licenses
- [ ] Docs updated (README, CHANGELOG, PRIVACY/PERMISSIONS if relevant)
