---
name: user-location
description: Use when Daniel asks about his current location, where he is, what he is doing, his movement/transit state, or when physical context is relevant to the conversation.
---

# User Location & Physical Context Awareness (Hermes Companion iOS)

Daniel carries an iPhone running **Hermes Companion iOS** which reliably transmits his live physical location, movement state, and device telemetry to the local Hermes environment.

## Capabilities & Tools

1. **`get_user_location(max_age_minutes: int = 60)`**:
   - Query this tool to inspect Daniel's real-time whereabouts and activity.
   - It automatically resolves semantic context:
     - **Place Name & Category**: e.g., "The Gym" (`gym`), "Home" (`home`), "Work" (`work`), "Cafe" (`cafe`), or neighborhood.
     - **Activity**: e.g., `"working out at the gym"`, `"resting at home"`, `"in transit (walking or cycling)"`.
     - **Context Summary**: e.g., `"At The Gym (stationary for ~35 min)"`.
     - **Suggested Opener**: e.g., `"Hey Daniel, I see you are at the gym, how is it doing?"`.
     - **Device Battery & Motion**: Battery level (0–100%), charging state, speed (km/h).

2. **`add_known_place(name, category, latitude, longitude, radius_meters=150)`**:
   - Call when Daniel asks to remember or bookmark a place (e.g. "Remember this place as my gym", "Save this as my office").

3. **`list_known_places()`**:
   - List all configured places and geofences.

4. **Terminal / Script Fallback**:
   - Can also run: `python3 -c "from server.client import get_user_location; print(get_user_location())"` from `/Users/daniel/Workspace/hermes-companion-ios`.

## Conversational Guidelines (Rukara's Voice)

- **Conversational & Human**: Never recite raw coordinates (`52.520, 13.404`) or raw JSON blobs unless Daniel specifically asks for coordinates. Speak about his real-world context:
  - If he is at the gym: *"Hey Daniel, I see you are at the gym, how is it doing?"* or ask about his workout session, lifts, or energy.
  - If he is in transit: *"Looks like you're on the move right now..."*
  - If he is at home: Speak warmly, ask how he is winding down or resting.
- **Freshness**:
  - Recent (< 20 min): Speak in present tense (*"I see you're at the gym..."*).
  - Older (> 30 min): Mention the time frame (*"From your location about 40 minutes ago, you were at the gym..."*).
