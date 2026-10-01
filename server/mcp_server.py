#!/usr/bin/env python3
"""
Hermes Location MCP (Model Context Protocol) Server
--------------------------------------------------
Exposes user location tools directly to Hermes Agent over stdio (JSON-RPC).

Tools Exposed:
  1. get_user_location(max_age_minutes=60)
     Returns the user's current GPS position, age, accuracy, speed, battery, and motion state.
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
from pathlib import Path

TOOLS_DEFINITION = [
    {
        "name": "get_user_location",
        "description": "Fetch the user's current physical location, semantic place context (e.g. at the gym, at home, at work, in transit), current activity, movement speed, battery, and data freshness reported by Hermes Companion on iOS.",
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
        "description": "Read the latest Apple Health snapshot from Hermes Companion: sleep, workouts, recovery, steps, and heart-rate vitals.",
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
        activity = data.get("activity", "stationary")
        context_summary = data.get("context_summary", f"{place_name} ({category})")
        greeting = data.get("suggested_greeting", f"At {place_name}.")

        motion = data.get("motion_activity")
        if data.get("motion_fresh") and motion and motion != "unknown":
            movement_line = f"• Movement: {motion} (CoreMotion, live {int(data.get('motion_age_seconds', 0))}s ago)"
        elif data.get("is_moving_now"):
            movement_line = f"• Movement: moving at {data.get('speed_kmh')} km/h"
        else:
            movement_line = "• Movement: stationary"

        result_text = (
            f"User Location & Semantic Context:\n"
            f"• Current Place: {place_name} ({category.upper()})\n"
            f"• Activity: {activity}\n"
            f"• Context Summary: {context_summary}\n"
            f"• Suggested Conversational Opener: \"{greeting}\"\n"
            f"{movement_line}\n"
            f"• Battery: {data.get('battery_percent')}% ({data.get('battery_state')})\n"
            f"• Coordinates: {data.get('coordinates')} (±{data.get('accuracy_meters', 0.0):.1f}m accuracy)\n"
            f"• Recorded: {data.get('recorded_at')} ({data.get('age_human')})\n"
            f"• Reported via: {data.get('trigger_source')} (App state: {data.get('app_state')})\n"
            f"• Maps Link: {data.get('maps_link')}\n"
        )
        minutes_since_move = int(data.get("minutes_since_last_move") or data.get("fix_age_minutes") or age_minutes)
        if data.get("is_moving_now") and not data.get("is_at_known_place"):
            result_text += (
                f"\nNote: GPS last rewrote {minutes_since_move} min ago (the phone writes only after an accepted move: "
                "30 m while moving, 150 m while stationary). CoreMotion says the user is moving now; place_name is the last written position."
            )
        elif minutes_since_move >= 1:
            result_text += (
                f"\nNote: GPS last changed {minutes_since_move} min ago. The iPhone rewrites "
                "latest_location.json only after an accepted move (30 m while moving, 150 m while stationary). "
                "The user is still at this place; a growing age means they have been here that long."
            )

        return {"content": [{"type": "text", "text": result_text}]}

    elif name == "get_location_history":
        limit = min(int(arguments.get("limit", 20)), 100)
        data = {"error": "No location history available."}
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
            lines.append(
                f"- {loc['recorded_at']}: {loc['latitude']:.5f}, {loc['longitude']:.5f} "
                f"(±{loc['accuracy']:.0f}m, {loc['source']})"
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

        lines = ["Apple Health:"]
        sleep = data.get("sleep")
        if sleep:
            lines.append(f"• Sleep: {sleep.get('formatted_duration', 'n/a')} ({sleep.get('quality_rating', '').upper()}) — {sleep.get('summary', '')}")
        else:
            lines.append("• Sleep: No sleep session recorded in the last 24h")

        workout = data.get("workout")
        if workout:
            active_str = "ACTIVE NOW" if workout.get("is_currently_active") else f"Finished ({workout.get('phase', 'recent')})"
            lines.append(f"• Workout: {workout.get('workout_type', 'Workout')} [{active_str}] — {workout.get('summary', '')}")
            if workout.get("active_calories"):
                lines.append(f"  Calories Burned: {int(workout['active_calories'])} kcal")
        else:
            lines.append("• Workout: No workouts recorded today")

        rhr = data.get("resting_heart_rate_bpm")
        hrv = data.get("heart_rate_variability_sdnn")
        steps = data.get("step_count_today", 0)
        cals = data.get("active_calories_today", 0)
        rec = data.get("recovery_status", "unknown").upper()
        lines.append(f"• Recovery: {rec} | Steps: {steps:,} | Active Cal: {int(cals)} kcal" + (f" | Resting HR: {int(rhr)} bpm" if rhr else "") + (f" | HRV: {int(hrv)} ms" if hrv else ""))

        ctx = data.get("conversational_context", {})
        if ctx.get("sleep_insight"):
            lines.append(f"• Sleep Insight: \"{ctx['sleep_insight']}\"")
        if ctx.get("workout_insight"):
            lines.append(f"• Workout Insight: \"{ctx['workout_insight']}\"")
        if ctx.get("nutrition_reminder"):
            lines.append(f"• Post-Workout Nutrition: \"{ctx['nutrition_reminder']}\"")

        openers = data.get("suggested_openers", [])
        if openers:
            lines.append(f"• Suggested Conversational Opener: \"{openers[0]}\"")

        lines.append(f"• Recorded: {data.get('recorded_at')} ({data.get('age_human')}) via {data.get('source_channel')}")
        return {"content": [{"type": "text", "text": "\n".join(lines)}]}

    elif name == "get_user_physical_context":
        loc_res = handle_call_tool("get_user_location", {})
        health_res = handle_call_tool("get_user_health", {})

        loc_text = loc_res["content"][0]["text"] if not loc_res.get("isError") else "Location: Unavailable"
        health_text = health_res["content"][0]["text"] if not health_res.get("isError") else "Health: Unavailable"

        combined = f"=== DANIEL'S PHYSICAL & BIOMETRIC CONTEXT ===\n\n{loc_text}\n\n{health_text}"
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
