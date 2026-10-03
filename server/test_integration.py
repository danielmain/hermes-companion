#!/usr/bin/env python3
"""
Integration test for the Hermes Companion macOS side.

The one and only transport from the iPhone is iCloud Drive / CloudKit sync, so
this test exercises that path end to end, with no relay, no TCP and no network:

  1. Raw payload -> formatted Hermes location schema (place context included).
  2. Raw payload -> formatted Hermes health schema.
  3. client.get_user_location / get_user_health reading a synced iCloud file.
  4. Combined physical context (location + health).
  5. MCP tools answered over JSON-RPC (get_user_location, get_user_health,
     list_known_places).

Fixtures are written to /tmp and injected at the top of the client's iCloud path
list, so the test is hermetic and never touches the real synced container.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Final, Mapping

REPO: Final[str] = str(Path(__file__).resolve().parents[1])
SERVER: Final[str] = os.path.join(REPO, "server")
sys.path.insert(0, SERVER)

LOCATION_FIXTURE: Final[Mapping[str, object]] = {
    "id": "ck-fix-001",
    "timestamp": "2026-09-28T21:40:55Z",
    "latitude": 48.858844,
    "longitude": 2.294351,
    "altitude": 35.0,
    "horizontal_accuracy": 3.2,
    "course": 90.0,
    "source": "CloudKit Private DB",
    "app_state": "background",
    "device_name": "iPhone",
}

HEALTH_FIXTURE: Final[Mapping[str, object]] = {
    "id": "ck-health-001",
    "device_name": "iPhone",
    "timestamp": "2026-09-29T08:30:00Z",
    "recovery_status": "recovered",
    "step_count_today": 8450,
    "active_calories_today": 450.0,
    "resting_heart_rate_bpm": 58.0,
    "heart_rate_variability_sdnn": 62.0,
    "sleep": {
        "total_sleep_minutes": 465,
        "total_hours": 7.75,
        "formatted_duration": "7h 45m",
        "deep_sleep_minutes": 95,
        "rem_sleep_minutes": 110,
        "quality_rating": "excellent",
        "summary": "Slept 7h 45m (Excellent Rest), 1h 35m deep, 1h 50m REM",
    },
    "workout": {
        "workout_type": "Strength Training",
        "category": "strength",
        "duration_minutes": 52,
        "active_calories": 420.0,
        "is_currently_active": False,
        "minutes_since_completion": 25,
        "phase": "just_finished",
        "summary": "Strength Training (52m, 420 kcal) finished 25m ago",
    },
    "conversational_context": {
        "sleep_insight": "I saw you had a wonderful 7h 45m of sleep last night! Feeling fully recharged today?",
        "workout_insight": "You just wrapped up your Strength Training workout (52m, 420 kcal)! How are you feeling?",
        "nutrition_reminder": "Time for your post-workout protein! Make sure you get 30-40g of protein and plenty of water in.",
        "recovery_summary": "Well Recovered",
    },
    "suggested_openers": [
        "Time for your post-workout protein! Make sure you get 30-40g of protein and plenty of water in."
    ],
}


def run_test() -> None:
    import client  # type: ignore[import-not-found,import-untyped]

    temp_loc = "/tmp/hermes_test_latest_location.json"
    temp_health = "/tmp/hermes_test_latest_health.json"
    temp_history = "/tmp/hermes_test_location_history.json"

    saved_loc_paths = list(client.ICLOUD_CONTAINER_PATHS)
    saved_health_paths = list(client.ICLOUD_HEALTH_CONTAINER_PATHS)
    saved_history_paths = list(client.ICLOUD_HISTORY_CONTAINER_PATHS)
    client.ICLOUD_CONTAINER_PATHS.insert(0, Path(temp_loc))
    client.ICLOUD_HEALTH_CONTAINER_PATHS.insert(0, Path(temp_health))
    client.ICLOUD_HISTORY_CONTAINER_PATHS.insert(0, Path(temp_history))

    try:
        print("1. Formatting a raw CloudKit location payload...")
        parsed = client.format_location_payload(LOCATION_FIXTURE, channel_name="iCloud Test")
        assert parsed is not None
        assert parsed["latitude"] == 48.858844
        assert parsed["accuracy_meters"] == 3.2
        assert "maps_link" in parsed
        assert "battery_percent" not in parsed
        assert "suggested_greeting" in parsed
        # Check still_there: old fix without fresh motion is unconfirmed
        assert parsed["still_there"] is False
        assert "unconfirmed" in parsed["still_there_status"]
        print(f"   Location format OK: {parsed['coordinates']} -> {parsed.get('place_name')}")

        print("2. Formatting a raw health payload...")
        parsed_h = client.format_health_payload(HEALTH_FIXTURE, channel_name="iCloud Test")
        assert parsed_h is not None
        assert parsed_h["sleep"] is not None and parsed_h["sleep"]["quality_rating"] == "excellent"
        assert parsed_h["workout"] is not None and parsed_h["workout"]["workout_type"] == "Strength Training"
        print(f"   Health format OK: {parsed_h['sleep']['formatted_duration']}, {parsed_h['workout']['summary']}")

        print("3. Writing synced iCloud fixtures and reading them zero-network...")
        with open(temp_loc, "w", encoding="utf-8") as f:
            json.dump(dict(LOCATION_FIXTURE), f)
        with open(temp_health, "w", encoding="utf-8") as f:
            json.dump(dict(HEALTH_FIXTURE), f)
        with open(temp_history, "w", encoding="utf-8") as f:
            json.dump({"records": [dict(LOCATION_FIXTURE)]}, f)

        loc = client.get_user_location(prefer_icloud=True)
        assert loc is not None and loc["latitude"] == 48.858844
        print(f"   get_user_location OK: {loc['coordinates']} ({loc['age_human']})")
        health = client.get_user_health(prefer_icloud=True)
        assert health is not None and health["sleep"] is not None and health["sleep"]["total_sleep_minutes"] == 465
        print(f"   get_user_health OK: {health['sleep']['formatted_duration']}")

        print("4. Resolving combined physical context...")
        ctx = client.get_user_physical_context(prefer_icloud=True)
        assert ctx["location"] is not None and ctx["health"] is not None
        print("   get_user_physical_context OK: location + health")

        print("5. Querying MCP tools over JSON-RPC (no relay)...")
        import mcp_server  # type: ignore[import-not-found,import-untyped]

        resp = mcp_server.process_message({
            "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {},
        })
        assert resp is not None and "result" in resp
        print(f"   MCP initialize: {resp['result']['serverInfo']}")  # type: ignore[index]

        raw_loc_call = mcp_server.process_message({
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": {"name": "get_user_location", "arguments": {}},
        })
        assert raw_loc_call is not None
        loc_res = raw_loc_call["result"]  # type: ignore[index]
        assert "error" not in loc_res, loc_res
        loc_text = loc_res["content"][0]["text"]
        assert "48.858844" in loc_text
        assert "facts_only:" in loc_text
        assert "Suggested" not in loc_text
        assert "battery" not in loc_text
        assert "speed" not in loc_text
        assert "still_there: unconfirmed" in loc_text
        print(f"   MCP get_user_location OK:\n{loc_text}")

        raw_health_call = mcp_server.process_message({
            "jsonrpc": "2.0", "id": 3, "method": "tools/call",
            "params": {"name": "get_user_health", "arguments": {}},
        })
        assert raw_health_call is not None
        health_res = raw_health_call["result"]  # type: ignore[index]
        health_text = health_res["content"][0]["text"]
        assert "Strength Training" in health_text
        assert "wonderful" not in health_text
        assert "protein" not in health_text.lower()
        assert "Suggested" not in health_text
        print(f"   MCP get_user_health OK:\n{health_text}")

        raw_places_call = mcp_server.process_message({
            "jsonrpc": "2.0", "id": 4, "method": "tools/call",
            "params": {"name": "list_known_places", "arguments": {}},
        })
        assert raw_places_call is not None
        places_res = raw_places_call["result"]  # type: ignore[index]
        print(f"   MCP list_known_places OK:\n{places_res['content'][0]['text']}")
        assert "I don't know where you are" not in loc_text
        assert "not as present certainty" not in loc_text

        raw_history_call = mcp_server.process_message({
            "jsonrpc": "2.0", "id": 5, "method": "tools/call",
            "params": {"name": "get_location_history", "arguments": {"limit": 5}},
        })
        assert raw_history_call is not None
        history_res = raw_history_call["result"]  # type: ignore[index]
        history_text = history_res["content"][0]["text"]
        assert "Recent" in history_text or "waypoints" in history_text
        print(f"   MCP get_location_history OK:\n{history_text}")

        print("6. Write-on-change: old GPS at a known place is still there...")
        import places as places_mod  # type: ignore[import-not-found,import-untyped]
        pm = places_mod.get_places_manager()
        homes = [p for p in pm.list_places() if p.category == "home"]
        assert homes, "expected a home place in places.json"
        home = homes[0]
        ctx_place = pm.resolve_context(
            home.latitude,
            home.longitude,
            is_moving=False,
            age_seconds=10800,
            motion_activity="stationary",
            motion_age_seconds=20,
        )
        assert ctx_place["is_at_known_place"] is True
        assert ctx_place["minutes_since_last_move"] == 180
        greet = (ctx_place.get("suggested_greeting") or "").lower()
        summary = (ctx_place.get("context_summary") or "").lower()
        assert "don't know" not in greet
        assert "last known" not in summary
        assert "still there" in summary
        print(f"   Old GPS at {ctx_place['place_name']}: {ctx_place['context_summary']}")

        print("\nAll integration tests passed successfully!")
    finally:
        client.ICLOUD_CONTAINER_PATHS[:] = saved_loc_paths
        client.ICLOUD_HEALTH_CONTAINER_PATHS[:] = saved_health_paths
        client.ICLOUD_HISTORY_CONTAINER_PATHS[:] = saved_history_paths
        for p in (temp_loc, temp_health, temp_history):
            if os.path.exists(p):
                os.remove(p)


if __name__ == "__main__":
    run_test()
