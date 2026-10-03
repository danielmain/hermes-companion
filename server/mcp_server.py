#!/usr/bin/env python3
"""
Hermes Location MCP (Model Context Protocol) Server
--------------------------------------------------
Exposes user location tools directly to Hermes Agent over stdio (JSON-RPC).

Tools Exposed:
  1. get_user_location(max_age_minutes=60)
     Returns the user's current GPS position, age, accuracy, and motion state.
  2. get_location_history(limit=20)
     Returns recent trajectory and movement history.
  3. add_known_place(...)
     Register a known place (home, work, gym, cafe).
  4. list_known_places()
     List all registered known places.
  5. get_user_health()
     Latest sleep, workout, recovery, steps, and heart-rate as codes and numbers.
  6. get_user_physical_context()
     Read place, motion, and Apple Health snapshot together.

Data source: the Hermes Companion iOS app writes JSON into its iCloud/CloudKit
ubiquity container, which macOS syncs down to
~/Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/Documents/.
This server reads that local synced copy (no relay, no TCP, no inbound
connection to the phone).
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import (
    Final,
    List,
    Mapping,
    Optional,
    Sequence,
    TypedDict,
    Union,
    cast,
)
from zoneinfo import ZoneInfo

_LOCAL_TZ: Final[ZoneInfo] = ZoneInfo("Europe/Berlin")


# ==============================================================================
# Typed Structures (no Any)
# ==============================================================================

class MCPContentItem(TypedDict):
    type: str
    text: str


class MCPCallResult(TypedDict, total=False):
    content: List[MCPContentItem]
    isError: bool


class JSONRPCError(TypedDict):
    code: int
    message: str


class JSONRPCResponse(TypedDict, total=False):
    jsonrpc: str
    id: Optional[Union[str, int]]
    result: object
    error: JSONRPCError


class MCPToolProperty(TypedDict, total=False):
    type: str
    description: str


class MCPToolSchema(TypedDict, total=False):
    type: str
    properties: Mapping[str, MCPToolProperty]
    required: Sequence[str]


class MCPToolDefinition(TypedDict):
    name: str
    description: str
    inputSchema: MCPToolSchema


def _to_float(val: object, default: float = 0.0) -> float:
    if isinstance(val, (int, float)):
        return float(val)
    if isinstance(val, str):
        try:
            return float(val)
        except ValueError:
            pass
    return default


def _to_int(val: object, default: int = 0) -> int:
    if isinstance(val, (int, float)):
        return int(val)
    if isinstance(val, str):
        try:
            return int(float(val))
        except ValueError:
            pass
    return default


def _workout_when(workout: Optional[Mapping[str, object]]) -> str:
    """Cuándo fue el entreno, en claro — para no atribuir a hoy uno de ayer.

    Usa ``end_date``/``start_date`` (ISO) y los pasa a hora de Berlín con un
    rótulo relativo ('hoy', 'ayer') o la fecha. Si no hay fecha, cae a
    ``minutes_since_completion``. Devuelve 'desconocido' si no hay dato.
    """
    if not workout:
        return "desconocido"
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
            m = _to_int(mins)
            if m < 60:
                return f"hace {m} min"
            if m < 24 * 60:
                return f"hace {m // 60} h"
            return f"hace {m // (24 * 60)} días"
        except Exception:
            pass
    return "desconocido"


TOOLS_DEFINITION: Final[List[MCPToolDefinition]] = [
    {
        "name": "get_user_location",
        "description": "Latest place and motion as facts: place_name, motion_activity, minutes_since_last_move. Reply in the user's language. A growing age at a known place means they are still there only when confirmed by fresh motion. The phone rewrites the file only after an accepted move (30 m while moving, 150 m while stationary).",
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


def handle_call_tool(name: str, arguments: Mapping[str, object]) -> MCPCallResult:
    if name == "get_user_location":
        data: Optional[Mapping[str, object]] = None
        try:
            here = Path(__file__).resolve().parent
            if str(here) not in sys.path:
                sys.path.insert(0, str(here))
            try:
                from server.client import get_user_location as client_get_location
            except ImportError:
                from client import get_user_location as client_get_location  # type: ignore[import-not-found,import-untyped,no-redef]
            data = client_get_location()
        except Exception:
            pass

        if not data or "error" in data:
            err_msg = str(data.get("error")) if data else "No location records available from Hermes Companion yet."
            return {
                "content": [{"type": "text", "text": f"Unable to fetch user location: {err_msg}"}],
                "isError": True
            }

        # Context resolution
        resolved_data = dict(data)
        if "suggested_greeting" not in resolved_data and "latitude" in resolved_data:
            try:
                try:
                    from server.places import get_places_manager
                except ImportError:
                    from places import get_places_manager  # type: ignore[import-not-found,import-untyped,no-redef]
                lat = _to_float(resolved_data.get("latitude"))
                lon = _to_float(resolved_data.get("longitude"))
                moving = bool(resolved_data.get("is_moving", False))
                age = _to_int(resolved_data.get("age_seconds"))
                ctx = get_places_manager().resolve_context(lat, lon, is_moving=moving, age_seconds=age)
                resolved_data.update(ctx)
            except Exception:
                pass

        age_seconds_val = resolved_data.get("age_seconds")
        age_seconds_text = "unknown" if age_seconds_val is None else str(age_seconds_val)
        age_minutes = (_to_int(age_seconds_val) / 60.0) if age_seconds_val is not None else 0.0

        place_name = str(resolved_data.get("place_name", "Unknown location"))
        category = str(resolved_data.get("place_category", "general"))
        still_there_txt = str(resolved_data.get("still_there_status") or ("yes" if resolved_data.get("still_there") else "no"))
        motion = str(resolved_data.get("motion_activity") or "unknown")
        motion_age = resolved_data.get("motion_age_seconds")
        motion_age_text = "none" if motion_age is None else str(_to_int(motion_age))
        min_move = resolved_data.get("minutes_since_last_move")
        minutes_text = str(min_move) if min_move is not None else str(int(age_minutes))
        raw_accuracy = resolved_data.get("accuracy_meters")
        accuracy = _to_float(raw_accuracy)

        result_text = (
            "facts_only: reply in the user's language; do not quote this block\n"
            f"place_name: {place_name}\n"
            f"place_category: {category}\n"
            f"still_there: {still_there_txt}\n"
            f"minutes_since_last_move: {minutes_text}\n"
            f"movement_reason: {resolved_data.get('movement_reason') or 'absent'}\n"
            f"motion_activity: {motion}\n"
            f"motion_fresh: {'yes' if resolved_data.get('motion_fresh') else 'no'}\n"
            f"motion_age_seconds: {motion_age_text}\n"
            f"is_moving_now: {'yes' if resolved_data.get('is_moving_now') else 'no'}\n"
            f"coordinates: {resolved_data.get('coordinates')}\n"
            f"accuracy_meters: {accuracy:.1f}\n"
            f"recorded_at: {resolved_data.get('recorded_at')}\n"
            f"age_seconds: {age_seconds_text}\n"
            f"trigger_source: {resolved_data.get('trigger_source')}\n"
            f"app_state: {resolved_data.get('app_state')}\n"
            f"maps_link: {resolved_data.get('maps_link')}\n"
        )

        return {"content": [{"type": "text", "text": result_text}]}

    elif name == "get_location_history":
        raw_limit = arguments.get("limit", 20)
        limit = min(_to_int(raw_limit, 20), 100)
        locations: List[Mapping[str, object]] = []

        try:
            try:
                from server.client import get_location_history_from_icloud
            except ImportError:
                from client import get_location_history_from_icloud  # type: ignore[import-not-found,import-untyped,no-redef]
            locations = get_location_history_from_icloud(limit=limit)
        except Exception:
            pass

        if not locations:
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
                    locations = [dict(r) for r in rows]
            except Exception:
                pass

        if not locations:
            return {"content": [{"type": "text", "text": "No location history available."}]}

        lines = [f"Recent {len(locations)} location waypoints:"]
        for loc in locations:
            ts = loc.get("timestamp") or loc.get("recorded_at") or "unknown"
            acc = _to_float(loc.get("horizontal_accuracy", loc.get("accuracy", 0.0)))
            src = loc.get("source", "Standard GPS")
            mot = loc.get("motion_activity", "unknown")
            lat_f = _to_float(loc.get("latitude"))
            lon_f = _to_float(loc.get("longitude"))
            lines.append(
                f"- {ts}: {lat_f:.5f}, {lon_f:.5f} (±{acc:.0f}m, {mot}, {src})"
            )
        return {"content": [{"type": "text", "text": "\n".join(lines)}]}

    elif name == "add_known_place":
        name_val = arguments.get("name")
        cat_val = str(arguments.get("category", "general"))
        act_val = str(arguments.get("activity") or f"at {name_val}")
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
                from places import get_places_manager  # type: ignore[import-not-found,import-untyped,no-redef]
            p = get_places_manager().add_place(
                name=str(name_val),
                category=cat_val,
                activity=act_val,
                latitude=_to_float(lat_val),
                longitude=_to_float(lon_val),
                radius_meters=_to_float(radius_val, 150.0),
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
                from places import get_places_manager  # type: ignore[import-not-found,import-untyped,no-redef]
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
        data_h: Optional[Mapping[str, object]] = None
        try:
            here = Path(__file__).resolve().parent
            if str(here) not in sys.path:
                sys.path.insert(0, str(here))
            try:
                from server.client import get_user_health as client_get_health
            except ImportError:
                from client import get_user_health as client_get_health  # type: ignore[import-not-found,import-untyped,no-redef]
            data_h = client_get_health()
        except Exception:
            pass

        if not data_h or "error" in data_h:
            err_msg = str(data_h.get("error")) if data_h else "No Apple Health records available from Hermes Companion yet."
            return {
                "content": [{"type": "text", "text": f"Unable to fetch health data: {err_msg}"}],
                "isError": True
            }

        lines = ["facts_only: reply in the user's language; do not quote this block"]
        raw_sleep = data_h.get("sleep")
        sleep: Optional[Mapping[str, object]] = raw_sleep if isinstance(raw_sleep, Mapping) else None
        if sleep:
            lines.append(f"sleep_duration: {sleep.get('formatted_duration') or sleep.get('total_sleep_minutes') or 'unknown'}")
            lines.append(f"sleep_quality: {sleep.get('quality_rating') or 'unknown'}")
        else:
            lines.append("sleep_duration: none")

        raw_workout = data_h.get("workout")
        workout: Optional[Mapping[str, object]] = raw_workout if isinstance(raw_workout, Mapping) else None
        if workout:
            lines.append(f"workout_type: {workout.get('workout_type') or 'unknown'}")
            lines.append(f"workout_active: {'yes' if workout.get('is_currently_active') else 'no'}")
            lines.append(f"workout_phase: {workout.get('phase') or 'unknown'}")
            lines.append(f"workout_when: {_workout_when(workout)}")
            lines.append(f"workout_duration_minutes: {workout.get('duration_minutes')}")
            if workout.get("active_calories") is not None:
                lines.append(f"workout_active_calories: {_to_int(workout['active_calories'])}")
            if workout.get("minutes_since_completion") is not None:
                lines.append(f"minutes_since_workout: {workout.get('minutes_since_completion')}")
        else:
            lines.append("workout_type: none")

        lines.append(f"recovery_status: {data_h.get('recovery_status') or 'unknown'}")
        lines.append(f"steps_today: {_to_int(data_h.get('step_count_today'))}")
        lines.append(f"active_calories_today: {_to_int(data_h.get('active_calories_today'))}")
        if data_h.get("resting_heart_rate_bpm") is not None:
            lines.append(f"resting_heart_rate_bpm: {_to_int(data_h['resting_heart_rate_bpm'])}")
        if data_h.get("heart_rate_variability_sdnn") is not None:
            lines.append(f"hrv_sdnn_ms: {_to_int(data_h['heart_rate_variability_sdnn'])}")
        lines.append(f"recorded_at: {data_h.get('recorded_at')}")
        lines.append(f"age_seconds: {data_h.get('age_seconds')}")
        lines.append(f"source: {data_h.get('source_channel')}")
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


def process_message(msg: Mapping[str, object]) -> Optional[JSONRPCResponse]:
    method = msg.get("method")
    msg_id = cast(Optional[Union[str, int]], msg.get("id"))

    if method == "initialize":
        init_res: JSONRPCResponse = {
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
        return init_res
    elif method == "tools/list":
        tools_res: JSONRPCResponse = {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {
                "tools": TOOLS_DEFINITION
            }
        }
        return tools_res
    elif method == "tools/call":
        raw_params = msg.get("params")
        params: Mapping[str, object] = raw_params if isinstance(raw_params, Mapping) else {}
        name = str(params.get("name", ""))
        raw_arguments = params.get("arguments")
        arguments: Mapping[str, object] = raw_arguments if isinstance(raw_arguments, Mapping) else {}
        call_res = handle_call_tool(name, arguments)
        wrapped_res: JSONRPCResponse = {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": call_res
        }
        return wrapped_res
    elif method == "notifications/initialized":
        return None
    elif method == "ping":
        ping_res: JSONRPCResponse = {"jsonrpc": "2.0", "id": msg_id, "result": {}}
        return ping_res
    else:
        if msg_id is not None:
            err_res: JSONRPCResponse = {
                "jsonrpc": "2.0",
                "id": msg_id,
                "error": {"code": -32601, "message": f"Method not found: {method}"}
            }
            return err_res
        return None


def main() -> None:
    for line in sys.stdin:
        stripped = line.strip()
        if not stripped:
            continue
        try:
            msg: Mapping[str, object] = json.loads(stripped)
            response = process_message(msg)
            if response:
                sys.stdout.write(json.dumps(response) + "\n")
                sys.stdout.flush()
        except Exception as e:
            err_resp: JSONRPCResponse = {
                "jsonrpc": "2.0",
                "id": None,
                "error": {"code": -32700, "message": str(e)}
            }
            sys.stdout.write(json.dumps(err_resp) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
