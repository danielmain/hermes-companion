# Reading Hermes Companion

The iPhone app writes `latest_location.json` and `latest_health.json` into the user's private iCloud container. On the Mac, read them with the skill or with the optional MCP server in this directory.

Personal voice, names, and schedules belong in the agent's own profile. This file only describes the data. It names no person and no agent.

## Language

The skill and this note are English so the model can read them. Reply in the user's language. Keep a place name exactly as it was saved. Translate codes such as `home`, `walking`, `In Transit`, `Unlisted place`, and `fatigued`. Do not quote `suggested_greeting`, `context_summary`, `suggested_openers`, or the English insight fields an older health file may still contain. The script's first line, `facts_only:`, means the block is data.

## Battery

Phone battery is not part of the agent reading. New `latest_location.json` files omit `battery_level` and `battery_state`. If an older file still has those keys, ignore them. The iPhone history screen can still show the level stored with each on-device fix.

## How to read

```bash
python3 skills/hermes-companion/scripts/companion.py
python3 skills/hermes-companion/scripts/companion.py --health
python3 skills/hermes-companion/scripts/companion.py --context
```

MCP tools, if the server is registered: `get_user_location`, `get_user_health`, `get_user_physical_context`, `list_known_places`, `add_known_place`.

```python
from server.client import get_user_location, get_user_health
```

Run that import from the repository root, or add the repository to `sys.path`.

## What the location file means

The timestamp is the last move the phone accepted.

- Fresh walking, running, cycling, or driving is stored at the distance filter (default 30 m).
- A fresh stationary reading is stored only past 150 m, or when GPS speed is above 1 m/s and the distance filter is also cleared.
- With no fresh motion sample, the distance filter alone applies.

A growing age at a known place means the user is still there. A new file is an accepted move. Speak in the present tense and do not announce an arrival from the timestamp alone.

`motion_activity` (`stationary`, `walking`, `running`, `cycling`, `automotive`) is what the body is doing now. Walking inside a saved place stays at that place. Automotive motion is in transit.

`movement_reason` is `moved`, `distance`, or `no_motion_reading`.

Name a place only after the user asks. Until then an unknown coordinate is an unlisted place.

## What the health file means

Sleep duration is the union of Deep, REM, and Core for the last clustered night. Use `recovery_status` (`recovered`, `moderate`, `fatigued`), the workout phase, and the step and heart-rate fields that are actually present. Do not invent a session that the snapshot does not contain.

Field lists are in `skills/hermes-companion/references/files.md`.
