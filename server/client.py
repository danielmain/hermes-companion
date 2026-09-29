"""
Hermes Location Python Client Helper
------------------------------------
Can be imported directly by Hermes Agent scripts.
Supports both native iCloud sync (Private DB / Ubiquity container)
and HTTP Relay endpoints.

Usage:
    from server.client import get_user_location
    loc = get_user_location()
    if loc:
        print(f"User is at {loc['latitude']}, {loc['longitude']}")
"""

import os
import json
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path

RELAY_URL = os.getenv("HERMES_RELAY_URL", "http://localhost:8080").rstrip("/")
RELAY_TOKEN = os.getenv("HERMES_RELAY_TOKEN", "")

ICLOUD_CONTAINER_PATHS = [
    Path.home() / "Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/Documents/latest_location.json",
    Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/HermesCompanion/latest_location.json",
    Path("/tmp/hermes_latest_location.json"),
]

def format_location_payload(data, channel_name="iCloud / CloudKit"):
    """Format raw location data dict to standard Hermes dictionary schema."""
    if not data or "latitude" not in data or "longitude" not in data:
        return None

    lat = float(data["latitude"])
    lon = float(data["longitude"])

    ts_str = data.get("timestamp") or data.get("recorded_at")
    age_sec = 0
    if ts_str:
        try:
            rec_dt = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
            age_sec = max(0, int((datetime.now(timezone.utc) - rec_dt).total_seconds()))
        except Exception:
            pass

    speed_mps = float(data.get("speed_mps", data.get("speed", -1.0)))
    speed_kmh = round(speed_mps * 3.6, 1) if speed_mps > 0 else 0.0

    bat_lvl = float(data.get("battery_level", -1.0))
    bat_pct = int(bat_lvl * 100) if bat_lvl >= 0 else None

    acc = float(data.get("horizontal_accuracy", data.get("accuracy", data.get("accuracy_meters", 0.0))))

    payload = {
        "status": "ok",
        "latitude": lat,
        "longitude": lon,
        "altitude_meters": float(data.get("altitude", data.get("altitude_meters", 0.0))),
        "accuracy_meters": acc,
        "horizontal_accuracy": acc,
        "speed_mps": speed_mps,
        "speed_kmh": speed_kmh,
        "is_moving": speed_kmh > 3.0,
        "recorded_at": ts_str,
        "age_seconds": age_sec,
        "age_human": f"{age_sec // 60}m {age_sec % 60}s ago" if age_sec >= 60 else f"{age_sec}s ago",
        "trigger_source": data.get("source", channel_name),
        "battery_percent": bat_pct,
        "battery_state": data.get("battery_state", "unknown"),
        "app_state": data.get("app_state", "active"),
        "device_name": data.get("device_name", "iPhone"),
        "coordinates": f"{lat:.6f}, {lon:.6f}",
        "maps_link": f"https://maps.apple.com/?ll={lat},{lon}&q=User+Location",
        "source_channel": channel_name
    }

    try:
        try:
            from server.places import get_places_manager
        except ImportError:
            from places import get_places_manager
        ctx = get_places_manager().resolve_context(
            lat,
            lon,
            speed_kmh=speed_kmh,
            is_moving=speed_kmh > 3.0,
            age_seconds=age_sec,
        )
        payload.update(ctx)
    except Exception:
        pass

    return payload

def get_user_location_from_icloud():
    """Read the latest location directly from local iCloud container files."""
    for path in ICLOUD_CONTAINER_PATHS:
        if path.is_file():
            try:
                with open(path, "r", encoding="utf-8") as f:
                    raw = json.load(f)
                    res = format_location_payload(raw, channel_name=f"iCloud ({path.name})")
                    if res:
                        return res
            except Exception:
                continue
    return None

def get_user_location_from_sqlite(db_path=None):
    """Read the latest location directly from local SQLite database."""
    target_db = Path(db_path) if db_path else Path(__file__).resolve().parent / "locations.sqlite3"
    if not target_db.is_file():
        return None
    try:
        import sqlite3
        conn = sqlite3.connect(target_db)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        cur.execute("SELECT * FROM locations ORDER BY recorded_at DESC LIMIT 1")
        row = cur.fetchone()
        conn.close()
        if row:
            raw = dict(row)
            return format_location_payload(raw, channel_name="SQLite (local)")
    except Exception:
        pass
    return None

def get_user_location(relay_url=None, token=None, prefer_icloud=True):
    """
    Fetch the latest location recorded from Hermes Companion iOS.
    Checks local synced iCloud storage first (zero latency, no open ports needed),
    falls back to HTTP relay server if available, and finally to local SQLite database.
    Always enriches with semantic place context (gym, home, transit, etc.).
    """
    data = None
    if prefer_icloud:
        data = get_user_location_from_icloud()

    if not data:
        url = f"{relay_url or RELAY_URL}/api/location/latest"
        req = urllib.request.Request(url)
        auth_token = token or RELAY_TOKEN
        if auth_token:
            req.add_header("Authorization", f"Bearer {auth_token}")

        try:
            with urllib.request.urlopen(req, timeout=1.5) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                data["source_channel"] = "HTTP Relay"
        except urllib.error.HTTPError as e:
            if e.code == 404:
                data = get_user_location_from_icloud() or get_user_location_from_sqlite()
            else:
                data = get_user_location_from_icloud() or get_user_location_from_sqlite()
        except Exception:
            data = get_user_location_from_icloud() or get_user_location_from_sqlite()

    if not data:
        data = get_user_location_from_sqlite()

    if data and "latitude" in data and "suggested_greeting" not in data:
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

    return data

def add_known_place(name, category, activity, latitude, longitude, radius_meters=150.0, notes=""):
    """Register a new known place (e.g. Daniel's gym, home, office)."""
    try:
        from server.places import get_places_manager
    except ImportError:
        from places import get_places_manager
    return get_places_manager().add_place(
        name=name,
        category=category,
        activity=activity,
        latitude=float(latitude),
        longitude=float(longitude),
        radius_meters=float(radius_meters),
        notes=notes,
    ).to_dict()

def list_known_places():
    """List all registered known places."""
    try:
        from server.places import get_places_manager
    except ImportError:
        from places import get_places_manager
    return [p.to_dict() for p in get_places_manager().list_places()]

