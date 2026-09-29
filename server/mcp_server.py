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

Configuration:
  Set HERMES_RELAY_URL environment variable (default: http://localhost:8080)
  Set HERMES_RELAY_TOKEN environment variable if Bearer auth is enabled.
"""

import sys
import os
import json
import urllib.request
import urllib.error

RELAY_URL = os.getenv("HERMES_RELAY_URL", "http://localhost:8080").rstrip("/")
RELAY_TOKEN = os.getenv("HERMES_RELAY_TOKEN", "")

def fetch_json(endpoint):
    url = f"{RELAY_URL}{endpoint}"
    req = urllib.request.Request(url)
    if RELAY_TOKEN:
        req.add_header("Authorization", f"Bearer {RELAY_TOKEN}")
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return {"error": "No location records available from Hermes Companion yet."}
        return {"error": f"HTTP Error {e.code}: {e.reason}"}
    except Exception as e:
        return {"error": f"Connection error to Hermes Relay at {url}: {str(e)}"}

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
        "description": "Register a new known place (e.g., gym, home, office, cafe) so Hermes automatically recognizes Daniel when he is there.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {
                    "type": "string",
                    "description": "Name of the place, e.g. 'The Gym' or 'John Reed Fitness' or 'Home'."
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
            relay_data = fetch_json("/api/location/latest")
            if not ("error" in relay_data and data):
                data = relay_data

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
        is_stale = age_minutes > max_age

        place_name = data.get("place_name", "Unknown location")
        category = data.get("place_category", "general")
        activity = data.get("activity", "stationary")
        context_summary = data.get("context_summary", f"{place_name} ({category})")
        greeting = data.get("suggested_greeting", f"Hey Daniel, I see you're at {place_name}, how is it going?")

        result_text = (
            f"User Location & Semantic Context:\n"
            f"• Current Place: {place_name} ({category.upper()})\n"
            f"• Activity: {activity}\n"
            f"• Context Summary: {context_summary}\n"
            f"• Suggested Conversational Opener: \"{greeting}\"\n"
            f"• Movement: {'Moving at ' + str(data['speed_kmh']) + ' km/h' if data.get('is_moving') else 'Stationary'}\n"
            f"• Battery: {data.get('battery_percent')}% ({data.get('battery_state')})\n"
            f"• Coordinates: {data.get('coordinates')} (±{data.get('accuracy_meters', 0.0):.1f}m accuracy)\n"
            f"• Recorded: {data.get('recorded_at')} ({data.get('age_human')})\n"
            f"• Reported via: {data.get('trigger_source')} (App state: {data.get('app_state')})\n"
            f"• Maps Link: {data.get('maps_link')}\n"
        )
        if is_stale:
            result_text += f"\n⚠️ Note: This location fix is {int(age_minutes)} minutes old (exceeds {max_age}m threshold)."

        return {"content": [{"type": "text", "text": result_text}]}

    elif name == "get_location_history":
        limit = min(int(arguments.get("limit", 20)), 100)
        data = fetch_json(f"/api/location/history?limit={limit}")
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
