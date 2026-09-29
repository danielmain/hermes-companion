"""
Hermes Location Python Client Helper
------------------------------------
Can be imported directly by Hermes Agent scripts.

The one and only transport from the iPhone is iCloud Drive / CloudKit sync: the
Hermes Companion iOS app writes JSON into the synced ubiquity container and this
module reads the local copy that macOS materialises on disk. No relay, no TCP,
no inbound connection to the phone (both devices are typically behind NAT).

Usage:
    from server.client import get_user_location
    loc = get_user_location()
    if loc:
        print(f"User is at {loc['latitude']}, {loc['longitude']}")
"""

import json
from datetime import datetime, timezone
from pathlib import Path

ICLOUD_CONTAINER_PATHS = [
    Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/HermesCompanion/latest_location.json",
    Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/Hermes Companion/latest_location.json",
    Path.home() / "Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/Documents/latest_location.json",
    Path.home() / "Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/latest_location.json",
    Path("/tmp/hermes_latest_location.json"),
]

ICLOUD_HEALTH_CONTAINER_PATHS = [
    Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/HermesCompanion/latest_health.json",
    Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/Hermes Companion/latest_health.json",
    Path.home() / "Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/Documents/latest_health.json",
    Path.home() / "Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/latest_health.json",
    Path("/tmp/hermes_latest_health.json"),
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

    # Real motion state from CoreMotion (independent of the GPS fix age).
    motion_activity = str(data.get("motion_activity", "unknown") or "unknown")
    motion_confidence = data.get("motion_confidence")
    motion_age_sec = 999999
    motion_ts_str = data.get("motion_timestamp")
    if motion_ts_str:
        try:
            mt = datetime.fromisoformat(str(motion_ts_str).replace("Z", "+00:00"))
            motion_age_sec = max(0, int((datetime.now(timezone.utc) - mt).total_seconds()))
        except Exception:
            pass

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
        "motion_activity": motion_activity,
        "motion_confidence": motion_confidence,
        "motion_timestamp": motion_ts_str,
        "motion_age_seconds": motion_age_sec,
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
            motion_activity=motion_activity,
            motion_age_seconds=motion_age_sec,
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

def get_user_location(prefer_icloud=True):
    """
    Fetch the latest location recorded by Hermes Companion iOS.
    Reads the locally synced iCloud/CloudKit file first (zero network, no open
    ports), then the local SQLite cache. Always enriches with semantic place
    context (gym, home, transit, etc.).
    """
    data = None
    if prefer_icloud:
        data = get_user_location_from_icloud()

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

def format_health_payload(data, channel_name="iCloud / CloudKit"):
    """Format raw health data dict to standard Hermes dictionary schema."""
    if not data or not isinstance(data, dict):
        return None

    ts_str = data.get("timestamp") or data.get("recorded_at")
    age_sec = 0
    if ts_str:
        try:
            rec_dt = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
            age_sec = max(0, int((datetime.now(timezone.utc) - rec_dt).total_seconds()))
        except Exception:
            pass

    age_human = f"{age_sec // 60}m {age_sec % 60}s ago" if age_sec >= 60 else f"{age_sec}s ago"
    payload = {
        "status": "ok",
        "id": data.get("id"),
        "recorded_at": ts_str,
        "age_seconds": age_sec,
        "age_human": age_human,
        "source_channel": channel_name,
        "recovery_status": data.get("recovery_status", "unknown"),
        "step_count_today": data.get("step_count_today", 0),
        "active_calories_today": data.get("active_calories_today", 0.0),
        "resting_heart_rate_bpm": data.get("resting_heart_rate_bpm"),
        "current_heart_rate_bpm": data.get("current_heart_rate_bpm"),
        "heart_rate_variability_sdnn": data.get("heart_rate_variability_sdnn"),
        "sleep": data.get("sleep"),
        "workout": data.get("workout"),
        "conversational_context": data.get("conversational_context", {}),
        "suggested_openers": data.get("suggested_openers", data.get("conversational_context", {}).get("suggestedOpeners", []))
    }
    return payload

def get_user_health_from_icloud():
    """Read the latest health snapshot directly from local iCloud container files."""
    for path in ICLOUD_HEALTH_CONTAINER_PATHS:
        if path.is_file():
            try:
                with open(path, "r", encoding="utf-8") as f:
                    raw = json.load(f)
                    res = format_health_payload(raw, channel_name=f"iCloud ({path.name})")
                    if res:
                        return res
            except Exception:
                continue
    return None

def get_user_health_from_sqlite(db_path=None):
    """Read the latest health snapshot directly from local SQLite database."""
    target_db = Path(db_path) if db_path else Path(__file__).resolve().parent / "locations.sqlite3"
    if not target_db.is_file():
        return None
    try:
        import sqlite3
        conn = sqlite3.connect(target_db)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        cur.execute("SELECT * FROM health_snapshots ORDER BY recorded_at DESC LIMIT 1")
        row = cur.fetchone()
        conn.close()
        if row:
            raw = dict(row)
            parsed = {}
            if raw.get("raw_payload"):
                try:
                    parsed = json.loads(raw["raw_payload"])
                except Exception:
                    pass
            if not parsed:
                parsed = {
                    "id": raw["id"],
                    "timestamp": raw["recorded_at"],
                    "recovery_status": raw["recovery_status"],
                    "step_count_today": raw["step_count"],
                    "active_calories_today": raw["active_calories"],
                    "sleep": {
                        "total_sleep_minutes": raw["sleep_duration_minutes"],
                        "formatted_duration": f"{raw['sleep_duration_minutes'] // 60}h {raw['sleep_duration_minutes'] % 60}m",
                        "quality_rating": raw["sleep_quality"],
                        "summary": raw["sleep_summary"]
                    } if raw["sleep_duration_minutes"] > 0 else None,
                    "workout": {
                        "workout_type": raw["workout_type"],
                        "duration_minutes": raw["workout_duration_minutes"],
                        "active_calories": raw["workout_calories"],
                        "is_currently_active": bool(raw["is_workout_active"]),
                        "summary": raw["workout_summary"]
                    } if raw["workout_type"] else None
                }
            return format_health_payload(parsed, channel_name="SQLite (local)")
    except Exception:
        pass
    return None

def get_user_health(prefer_icloud=True):
    """
    Fetch the latest Apple Health snapshot from Hermes Companion.
    Reads the locally synced iCloud/CloudKit file first (zero network), then the
    local SQLite cache.
    """
    data = None
    if prefer_icloud:
        data = get_user_health_from_icloud()

    if not data:
        data = get_user_health_from_sqlite()

    return data

def get_user_physical_context(prefer_icloud=True):
    """
    Unified physical context combining physical location (e.g. at the gym, at home)
    and Apple Health telemetry (sleep quality, active workout, post-workout recovery, vitals).
    """
    loc = get_user_location(prefer_icloud=prefer_icloud)
    health = get_user_health(prefer_icloud=prefer_icloud)
    return {
        "location": loc,
        "health": health,
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

