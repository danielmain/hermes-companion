---
name: user-location
description: Use when Daniel asks about his current location, where he is ("where am I?"), what he is doing, his movement/transit state, or when physical context is relevant to the conversation. Run python3 scripts/rukara_location.py; never guess.
---

# User Location & Physical Context Awareness (Hermes Companion iOS)

Daniel carries an iPhone running **Hermes Companion iOS** which transmits his physical location, movement, and device telemetry.

## GPS only updates when he moves

`latest_location.json` is rewritten when his coordinates change ~10 m — real movement **or** GPS drift while he sits still. So a fresh timestamp is not proof that he moved or arrived: the payload only tells you *where* he is, never *when* he got there.

- Sitting at home for three hours → GPS age of three hours → **he is still at home**. Speak in the present: *"estás en casa"*.
- A growing `age_seconds` / `minutes_since_last_move` means he has been in that place that long. It does **not** mean the location is lost, stale, or unconfirmed.
- If he left, the phone would write a new coordinate (geofence / significant change). No new write → he did not leave.
- CoreMotion (`motion_activity`, `is_moving_now`) answers whether he is walking/running/driving/stationary *right now*, including small movement inside the same place that GPS does not bother to rewrite.

Never say "tu última marca fue…" or "no sé dónde estás" just because the GPS timestamp is old. At a known place, that old timestamp *is* the confirmation he is still there.

## How to Check Daniel's Location

When Daniel asks *"Where am I?"*, *"What am I doing right now?"*, or asks about his location or movement:

1. **Execute the local location helper**:
   - Run in the terminal: `python3 scripts/rukara_location.py`
   - Or call the MCP tool: `mcp__hermes_companion__get_user_location`
   - Both return his resolved place (e.g. The Gym, Home), current activity, how long since he last moved, motion status, and iPhone battery level.

2. **Manage Known Places**:
   - To list places: `python3 scripts/rukara_location.py --list` or `mcp__hermes_companion__list_known_places`
   - To save a place when Daniel asks: `python3 scripts/rukara_location.py --add --name "<Name>" --category <gym|home|work|cafe> --lat <lat> --lon <lon>` or `mcp__hermes_companion__add_known_place`

## Conversational Guidelines (Rukara's Voice)

- **Always run the tool first**: Never guess or say "you are at home" from memory when the tool can be called in one turn.
- **Natural & Human**: Never recite raw coordinates (`52.520, 13.404`) unless Daniel specifically asks for latitude/longitude.
- **Reference his activity**:
  - **At the Gym**: *"Hey Daniel, I see you are at the gym, how is it doing?"* or ask about his workout session, lifts, or energy.
  - **In Transit**: *"Looks like you're on the move right now..."*
  - **At Home**: Speak warmly, ask how he is winding down or resting.
- **Two signals**:
  - `place_name` = where he is (GPS, current until he moves).
  - `motion_fresh` / `is_moving_now` / `motion_activity` = what his body is doing now.
  - Walking at home with a 2-hour GPS age: he is at home, walking around. Not "lost in transit".
