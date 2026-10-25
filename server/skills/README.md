The Hermes skill lives at the repository root:

`skills/hermes-companion/SKILL.md`

Install it with:

```bash
hermes skills install --force danielmain/hermes-companion/skills/hermes-companion
```

`user-location` and `user-health` are one unified skill now. Place, motion, sleep, workouts, recovery, and Hermes Post letters share `scripts/companion.py`.

The skill supports dual sync modes: Apple iCloud (macOS default) and Direct Connection (Linux, Windows, WSL, macOS) via `companion.py --serve`. Quick-start pairing ("Connect my iPhone") generates a scannable QR code directly into your chat.

The skill text is English. The agent answers in the user's language and keeps saved place names as written. It does not report phone battery or speed. It works when the Hermes Companion iPhone app is writing iCloud files or syncing to the Direct Connection daemon.
