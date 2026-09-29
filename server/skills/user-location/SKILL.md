---
name: user-location
description: Use when Daniel asks about his current location, where he is ("where am I?"), what he is doing, his movement/transit state, or when physical context is relevant to the conversation. Run python3 scripts/rukara_location.py; never guess.
---

# User Location & Physical Context Awareness (Hermes Companion iOS)

Daniel carries an iPhone running **Hermes Companion iOS** which reliably transmits his live physical location, movement state, and device telemetry to the local Hermes environment.

## How to Check Daniel's Location

When Daniel asks *"Where am I?"*, *"What am I doing right now?"*, or asks about his location or movement:

1. **Execute the local location helper**:
   - Run in the terminal: `python3 scripts/rukara_location.py`
   - Or call the MCP tool: `mcp__hermes_companion__get_user_location`
   - Both return his resolved place (e.g. The Gym, Home), current activity (e.g. working out), duration stationary, motion status, and iPhone battery level.

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
- **Freshness**:
  - Recent (< 20 min): Speak in present tense (*"I see you're at the gym..."*).
  - Older (> 30 min): Mention the time frame (*"From your location about 40 minutes ago, you were at the gym..."*).
