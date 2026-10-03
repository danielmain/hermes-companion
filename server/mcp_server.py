#!/usr/bin/env python3
"""
Hermes Location MCP (Model Context Protocol) Server
--------------------------------------------------
Exposes user location tools directly to Hermes Agent over stdio (JSON-RPC).

Tools Exposed:
  1. get_user_location(max_age_minutes=60)
     Returns the user's current GPS position, age, accuracy, speed, and motion state.
  2. get_location_history(limit=20)
     Returns recent trajectory and movement history.

Data source: the Hermes Companion iOS app writes JSON into its iCloud/CloudKit
ubiquity container, which macOS syncs down to
~/Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/Documents/.
This server reads that local synced copy (no relay, no TCP, no inbound
connection to the phone).
"""

import sys
import json
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

_LOCAL_TZ = ZoneInfo("Europe/Berlin")


def _workout_when(workout: dict) -> str:
    """Cuándo fue el entreno, en claro — para no atribuir a hoy uno de ayer.

    Usa ``end_date``/``start_date`` (ISO) y los pasa a hora de Berlín con un
    rótulo relativo ('hoy', 'ayer') o la fecha. Si no hay fecha, cae a
    ``minutes_since_completion``. Devuelve 'desconocido' si no hay dato.
    """
    end = workout.get("end_date") or workout.get("start_date")
    if end:
        try:
            dt = datetime.fromisoformat(str(end).replace("Z", "+00:00")).astimezone(_LOCAL_TZ)
            today = datetime.now(_LOCAL_TZ).date()
            d = dt.date()
            rel = "hoy" if d == today else ("ayer" if d == today - timedelta(days=1) else d.isoformat())
            return f"{rel} {dt.strftime('%H:%M')}"
        except Exception:
            pass
    mins = workout.get("minutes_since_completion")
    if mins is not None:
        try:
            m = int(mins)
            if m < 60:
                return f"hace {m} min"
            if m < 24 * 60:
                return f"hace {m // 60} h"
            return f"hace {m // (24 * 60)} días"
        except Exception:
            pass
    return "desconocido"


TOOLS_DEFINITION = [
    {
        "name": "get_user_location",
        "description": "Latest place and motion as facts: place_name, motion_activity, minutes_since_last_move. Reply in the user's language. A growing age at a known place means they are still there. The phone rewrites the file only after an accepted move (30 m while moving, 150 m while stationary).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "max_age_minutes": {
                    "type": "integer",
                    "description": "Maximum acceptable age of the location fix in minutes. Defaults to 60 minutes."
                }
            }
        }
    },
    {
        "name": "get_location_history",
        "description": "Fetch a list of recent location waypoints to understand where the user traveled recently.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "limit": {
                    "type": "integer",
                    "description": "Number of recent locations to return (max 100, default 20)."
                }
            }
        }
    },
    {
        "name": "add_known_place",
        "description": "Register a known place (home, work, gym, cafe) so later fixes inside its radius resolve to that name.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {
                    "type": "string",
                    "description": "Name of the place, for example Home or Gym."
                },
                "category": {
                    "type": "string",
                    "description": "Category: 'gym', 'home', 'work', 'cafe', 'outdoors', or 'general'."
                },
                "activity": {
                    "type": "string",
                    "description": "Description of activity when here, e.g. 'working out at the gym' or 'relaxing at home'."
                },
                "latitude": {
                    "type": "number",
                    "description": "GPS Latitude in decimal degrees."
                },
                "longitude": {
                    "type": "number",
                    "description": "GPS Longitude in decimal degrees."
                },
                "radius_meters": {
                    "type": "number",
                    "description": "Geofence radius in meters (default 150m)."
                }
            },
            "required": ["name", "category", "latitude", "longitude"]
        }
    },
    {
        "name": "list_known_places",
        "description": "List all registered known places (geofenced locations) configured in Hermes Companion.",
        "inputSchema": {
            "type": "object",
            "properties": {}
        }
    },
    {
        "name": "get_user_health",
        "description": "Latest sleep, workout, recovery, steps, and heart-rate as codes and numbers. Reply in the user's language. Do not recite English sentences stored in the health file.",
        "inputSchema": {
            "type": "object",
            "properties": {}
        }
    },
    {
        "name": "get_user_physical_context",
        "description": "Read place, motion, and the Apple Health snapshot together.",
        "inputSchema": {
            "type": "object",
            "properties": {}
        }
    }
]

def handle_call_tool(name, arguments):
    if name == "get_user_location":
        max_age = arguments.get("max_age_minutes", 60)
        data = None
        try:
            here = Path(__file__).resolve().parent
            if str(here) not in sys.path:
                sys.path.insert(0, str(here))
            from client import get_user_location as client_get_location
            data = client_get_location()
        except Exception:
            pass

        if not data or "error" in data:
            err_msg = data.get("error") if data else "No location records available from Hermes Companion yet."
            return {
                "content": [{"type": "text", "text": f"Unable to fetch user location: {err_msg}"}],
                "isError": True
            }

        # Ensure context resolution is present
        if "suggested_greeting" not in data and "latitude" in data:
            try:
                try:
                    from server.places import get_places_manager
                except ImportError:
                    from places import get_places_manager
                lat = float(data["latitude"])
                lon = float(data["longitude"])
                speed = float(data.get("speed_kmh", 0.0))
                moving = bool(data.get("is_moving", speed > 3.0))
                age = int(data.get("age_seconds", 0))
                ctx = get_places_manager().resolve_context(lat, lon, speed_kmh=speed, is_moving=moving, age_seconds=age)
                data.update(ctx)
            except Exception:
                pass

        age_seconds = data.get("age_seconds", 0)
        age_minutes = age_seconds / 60.0

        place_name = data.get("place_name", "Unknown location")
        category = data.get("place_category", "general")
        motion = data.get("motion_activity") or "unknown"
        motion_age = data.get("motion_age_seconds")
        motion_age_text = "none" if motion_age is None else str(int(motion_age))
        minutes_since_move = int(data.get("minutes_since_last_move") or data.get("fix_age_minutes") or age_minutes)
        accuracy = float(data.get("accuracy_meters") or 0.0)

        result_text = (
            "facts_only: reply in the user's language; do not quote this block\n"
            f"place_name: {place_name}\n"
            f"place_category: {category}\n"
            f"still_there: yes\n"
            f"minutes_since_last_move: {minutes_since_move}\n"
            f"movement_reason: {data.get('movement_reason') or 'absent'}\n"
            f"motion_activity: {motion}\n"
            f"motion_fresh: {'yes' if data.get('motion_fresh') else 'no'}\n"
            f"motion_age_seconds: {motion_age_text}\n"
            f"is_moving_now: {'yes' if data.get('is_moving_now') else 'no'}\n"
            f"speed_kmh: {data.get('speed_kmh')}\n"
            f"coordinates: {data.get('coordinates')}\n"
            f"accuracy_meters: {accuracy:.1f}\n"
            f"recorded_at: {data.get('recorded_at')}\n"
            f"age_seconds: {age_seconds}\n"
            f"trigger_source: {data.get('trigger_source')}\n"
            f"app_state: {data.get('app_state')}\n"
            f"maps_link: {data.get('maps_link')}\n"
        )

        return {"content": [{"type": "text", "text": result_text}]}

    elif name == "get_location_history":
        limit = min(int(arguments.get("limit", 20)), 100)
        data = {"error": "No location history available."}
        try:
            from client import get_location_history_from_icloud
            icloud_history = get_location_history_from_icloud(limit=limit)
            if icloud_history:
                data = {"count": len(icloud_history), "locations": icloud_history}
        except Exception:
            pass

        if "error" in data:
            try:
                import sqlite3
                db_path = Path(__file__).resolve().parent / "locations.sqlite3"
                if db_path.is_file():
                    conn = sqlite3.connect(db_path)
                    conn.row_factory = sqlite3.Row
                    cur = conn.cursor()
                    cur.execute("SELECT * FROM locations ORDER BY recorded_at DESC LIMIT ?", (limit,))
                    rows = cur.fetchall()
                    conn.close()
                    data = {"count": len(rows), "locations": [dict(r) for r in rows]}
            except Exception:
                pass

        if "error" in data:
            return {
                "content": [{"type": "text", "text": f"Unable to fetch location history: {data['error']}"}],
                "isError": True
            }

        locations = data.get("locations", [])
        if not locations:
            return {"content": [{"type": "text", "text": "No location history available."}]}

        lines = [f"Recent {len(locations)} location waypoints:"]
        for loc in locations:
            ts = loc.get("timestamp") or loc.get("recorded_at") or "unknown"
            acc = float(loc.get("horizontal_accuracy", loc.get("accuracy", 0.0)) or 0.0)
            src = loc.get("source", "Standard GPS")
            mot = loc.get("motion_activity", "unknown")
            lines.append(
                f"- {ts}: {float(loc['latitude']):.5f}, {float(loc['longitude']):.5f} "
                f"(±{acc:.0f}m, {mot}, {src})"
            )
        return {"content": [{"type": "text", "text": "\n".join(lines)}]}

    elif name == "add_known_place":
        name_val = arguments.get("name")
        cat_val = arguments.get("category", "general")
        act_val = arguments.get("activity") or f"at {name_val}"
        lat_val = arguments.get("latitude")
        lon_val = arguments.get("longitude")
        radius_val = arguments.get("radius_meters", 150.0)

        if not name_val or lat_val is None or lon_val is None:
            return {
                "content": [{"type": "text", "text": "Error: 'name', 'latitude', and 'longitude' are required."}],
                "isError": True
            }

        try:
            try:
                from server.places import get_places_manager
            except ImportError:
                from places import get_places_manager
            p = get_places_manager().add_place(
                name=name_val,
                category=cat_val,
                activity=act_val,
                latitude=float(lat_val),
                longitude=float(lon_val),
                radius_meters=float(radius_val),
            )
            return {
                "content": [
                    {
                        "type": "text",
                        "text": f"Successfully registered place '{p.name}' ({p.category}) at {p.latitude:.5f}, {p.longitude:.5f} (radius: {p.radius_meters}m)."
                    }
                ]
            }
        except Exception as e:
            return {
                "content": [{"type": "text", "text": f"Error registering place: {str(e)}"}],
                "isError": True
            }

    elif name == "list_known_places":
        try:
            try:
                from server.places import get_places_manager
            except ImportError:
                from places import get_places_manager
            places = get_places_manager().list_places()
            if not places:
                return {"content": [{"type": "text", "text": "No known places registered yet."}]}

            lines = [f"Registered Known Places ({len(places)} total):"]
            for p in places:
                lines.append(
                    f"• {p.name} [{p.category.upper()}] — {p.activity} "
                    f"({p.latitude:.5f}, {p.longitude:.5f}, radius: {p.radius_meters:.0f}m)"
                )
            return {"content": [{"type": "text", "text": "\n".join(lines)}]}
        except Exception as e:
            return {
                "content": [{"type": "text", "text": f"Error listing places: {str(e)}"}],
                "isError": True
            }

    elif name == "get_user_health":
        data = None
        try:
            here = Path(__file__).resolve().parent
            if str(here) not in sys.path:
                sys.path.insert(0, str(here))
            from client import get_user_health as client_get_health
            data = client_get_health()
        except Exception:
            pass

        if not data or "error" in data:
            err_msg = data.get("error") if data else "No Apple Health records available from Hermes Companion yet."
            return {
                "content": [{"type": "text", "text": f"Unable to fetch health data: {err_msg}"}],
                "isError": True
            }

        lines = ["facts_only: reply in the user's language; do not quote this block"]
        sleep = data.get("sleep") if isinstance(data.get("sleep"), dict) else None
        if sleep:
            lines.append(f"sleep_duration: {sleep.get('formatted_duration') or sleep.get('total_sleep_minutes') or 'unknown'}")
            lines.append(f"sleep_quality: {sleep.get('quality_rating') or 'unknown'}")
        else:
            lines.append("sleep_duration: none")

        workout = data.get("workout") if isinstance(data.get("workout"), dict) else None
        if workout:
            lines.append(f"workout_type: {workout.get('workout_type') or 'unknown'}")
            lines.append(f"workout_active: {'yes' if workout.get('is_currently_active') else 'no'}")
            lines.append(f"workout_phase: {workout.get('phase') or 'unknown'}")
            lines.append(f"workout_when: {_workout_when(workout)}")
            lines.append(f"workout_duration_minutes: {workout.get('duration_minutes')}")
            if workout.get("active_calories") is not None:
                lines.append(f"workout_active_calories: {int(workout['active_calories'])}")
            if workout.get("minutes_since_completion") is not None:
                lines.append(f"minutes_since_workout: {workout.get('minutes_since_completion')}")
        else:
            lines.append("workout_type: none")

        lines.append(f"recovery_status: {data.get('recovery_status') or 'unknown'}")
        lines.append(f"steps_today: {data.get('step_count_today') or 0}")
        lines.append(f"active_calories_today: {int(float(data.get('active_calories_today') or 0))}")
        if data.get("resting_heart_rate_bpm") is not None:
            lines.append(f"resting_heart_rate_bpm: {int(data['resting_heart_rate_bpm'])}")
        if data.get("heart_rate_variability_sdnn") is not None:
            lines.append(f"hrv_sdnn_ms: {int(data['heart_rate_variability_sdnn'])}")
        lines.append(f"recorded_at: {data.get('recorded_at')}")
        lines.append(f"age_seconds: {data.get('age_seconds')}")
        lines.append(f"source: {data.get('source_channel')}")
        return {"content": [{"type": "text", "text": "\n".join(lines)}]}

    elif name == "get_user_physical_context":
        loc_res = handle_call_tool("get_user_location", {})
        health_res = handle_call_tool("get_user_health", {})

        loc_text = loc_res["content"][0]["text"] if not loc_res.get("isError") else "Location: Unavailable"
        health_text = health_res["content"][0]["text"] if not health_res.get("isError") else "Health: Unavailable"

        combined = f"{loc_text}\n\n{health_text}"
        return {"content": [{"type": "text", "text": combined}]}

    else:
        return {
            "content": [{"type": "text", "text": f"Unknown tool: {name}"}],
            "isError": True
        }

def process_message(msg):
    method = msg.get("method")
    msg_id = msg.get("id")

    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {
                    "tools": {}
                },
                "serverInfo": {
                    "name": "hermes-location-mcp",
                    "version": "1.0.0"
                }
            }
        }
    elif method == "tools/list":
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {
                "tools": TOOLS_DEFINITION
            }
        }
    elif method == "tools/call":
        params = msg.get("params", {})
        name = params.get("name")
        arguments = params.get("arguments", {})
        result = handle_call_tool(name, arguments)
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": result
        }
    elif method == "notifications/initialized":
        return None
    elif method == "ping":
        return {"jsonrpc": "2.0", "id": msg_id, "result": {}}
    else:
        if msg_id is not None:
            return {
                "jsonrpc": "2.0",
                "id": msg_id,
                "error": {"code": -32601, "message": f"Method not found: {method}"}
            }
        return None

def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
            response = process_message(msg)
            if response:
                sys.stdout.write(json.dumps(response) + "\n")
                sys.stdout.flush()
        except Exception as e:
            err_resp = {
                "jsonrpc": "2.0",
                "id": None,
                "error": {"code": -32700, "message": str(e)}
            }
            sys.stdout.write(json.dumps(err_resp) + "\n")
            sys.stdout.flush()

if __name__ == "__main__":
    main()
