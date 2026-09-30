#!/usr/bin/env python3
"""Daniel's physical location & places manager for Rukara (Hermes Love Profile).

Interacts with the Hermes Companion iOS pipeline, reads Daniel's live physical context,
and manages known places in state/places.json.

Usage:
  python3 scripts/rukara_location.py              # Print current location & physical context
  python3 scripts/rukara_location.py --json       # Print raw JSON location payload
  python3 scripts/rukara_location.py --list       # List all known places from state/places.json
  python3 scripts/rukara_location.py --add --name "The Gym" --category gym --activity "working out" --lat 52.5200 --lon 13.4050
  python3 scripts/rukara_location.py --remove <id>
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

HERE = Path(__file__).resolve().parent
PROFILE = HERE.parent
STATE_DIR = PROFILE / "state"
PLACES_FILE = STATE_DIR / "places.json"

COMPANION_DIR = Path("/Users/daniel/Workspace/hermes-companion-ios")
if str(COMPANION_DIR) not in sys.path:
    sys.path.insert(0, str(COMPANION_DIR))

try:
    from server.client import get_user_location
    from server.places import PlacesManager, haversine_distance_meters
except ImportError:
    get_user_location = None
    PlacesManager = None


def _load_places() -> List[Dict[str, Any]]:
    if not PLACES_FILE.is_file():
        return []
    try:
        data = json.loads(PLACES_FILE.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except Exception:
        return []


def _save_places(places: List[Dict[str, Any]]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    PLACES_FILE.write_text(json.dumps(places, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def cmd_status(as_json: bool = False) -> int:
    if get_user_location is None:
        print("Error: Could not import get_user_location from companion repository.", file=sys.stderr)
        return 1

    loc = get_user_location()
    if not loc or loc.get("status") != "ok":
        print("No recent location recorded from Daniel's iPhone.")
        return 0

    if as_json:
        print(json.dumps(loc, indent=2, ensure_ascii=False))
        return 0

    place = loc.get("place_name", "Desconocido")
    cat = loc.get("place_category", "general")
    activity = loc.get("activity", "estacionario")
    greeting = loc.get("suggested_greeting", "")
    battery = loc.get("battery_percent")
    bat_state = loc.get("battery_state", "unknown")
    age = loc.get("age_human", "")
    coords = loc.get("coordinates", "")
    moving = loc.get("is_moving", False)
    speed = loc.get("speed_kmh", 0.0)

    print(f"Daniel's Physical Context:")
    print(f"• Lugar actual: {place} [{cat.upper()}]")
    print(f"• Actividad: {activity}")
    print(f"• Movimiento: {'En tránsito a ' + str(speed) + ' km/h' if moving else 'Estacionario'}")
    print(f"• Batería: {battery}% ({bat_state})")
    print(f"• Coordenadas: {coords}")
    print(f"• Último movimiento GPS: hace {age} (el archivo solo se reescribe cuando se mueve ~10 m; sigue en este lugar)")
    if greeting:
        print(f"• Sugerencia conversacional: \"{greeting}\"")
    return 0


def cmd_list() -> int:
    places = _load_places()
    if not places:
        print(f"No places configured in {PLACES_FILE}")
        return 0

    print(f"Known Places ({len(places)} defined in state/places.json):")
    for p in places:
        pid = p.get("id", p.get("name", "").lower().replace(" ", "_"))
        name = p.get("name", "Unknown")
        cat = p.get("category", "general")
        act = p.get("activity", f"at {name}")
        lat = p.get("latitude", 0.0)
        lon = p.get("longitude", 0.0)
        rad = p.get("radius_meters", 150.0)
        print(f"• [{pid}] {name} ({cat}) — {act} | {lat:.5f}, {lon:.5f} (±{rad:.0f}m)")
    return 0


def cmd_add(name: str, category: str, activity: Optional[str], lat: float, lon: float, radius: float, notes: str) -> int:
    places = _load_places()
    pid = name.lower().replace(" ", "_")
    act = activity or f"at {name}"

    updated = False
    for i, p in enumerate(places):
        if p.get("id") == pid or p.get("name") == name:
            places[i] = {
                "id": pid,
                "name": name,
                "category": category,
                "activity": act,
                "latitude": lat,
                "longitude": lon,
                "radius_meters": radius,
                "notes": notes,
            }
            updated = True
            break

    if not updated:
        places.append({
            "id": pid,
            "name": name,
            "category": category,
            "activity": act,
            "latitude": lat,
            "longitude": lon,
            "radius_meters": radius,
            "notes": notes,
        })

    _save_places(places)
    print(f"✓ Saved place '{name}' ({category}) to {PLACES_FILE}")
    return 0


def cmd_remove(place_id: str) -> int:
    places = _load_places()
    new_places = [p for p in places if p.get("id") != place_id and p.get("name") != place_id]
    if len(new_places) == len(places):
        print(f"Place '{place_id}' not found.")
        return 1

    _save_places(new_places)
    print(f"✓ Removed place '{place_id}' from {PLACES_FILE}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Daniel's physical location & places manager for Rukara.")
    parser.add_argument("--json", action="store_true", help="Print raw JSON status")
    parser.add_argument("--list", action="store_true", help="List all known places")
    parser.add_argument("--add", action="store_true", help="Add or update a known place")
    parser.add_argument("--remove", type=str, help="Remove a known place by ID or name")
    parser.add_argument("--name", type=str, help="Name of the place")
    parser.add_argument("--category", type=str, default="general", help="Category: gym, home, work, cafe, etc.")
    parser.add_argument("--activity", type=str, default=None, help="Activity description (e.g. 'working out at the gym')")
    parser.add_argument("--lat", type=float, help="Latitude")
    parser.add_argument("--lon", type=float, help="Longitude")
    parser.add_argument("--radius", type=float, default=150.0, help="Geofence radius in meters (default: 150m)")
    parser.add_argument("--notes", type=str, default="", help="Optional notes")

    args = parser.parse_args()

    if args.list:
        return cmd_list()
    elif args.remove:
        return cmd_remove(args.remove)
    elif args.add:
        if not args.name or args.lat is None or args.lon is None:
            print("Error: --name, --lat, and --lon are required when using --add", file=sys.stderr)
            return 1
        return cmd_add(args.name, args.category, args.activity, args.lat, args.lon, args.radius, args.notes)
    else:
        return cmd_status(as_json=args.json)


if __name__ == "__main__":
    sys.exit(main())
