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

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import (
    Final,
    List,
    Mapping,
    Optional,
    Sequence,
    Tuple,
    TypedDict,
    Union,
)

ICLOUD_CONTAINER_PATHS: Final[List[Path]] = [
    Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/HermesCompanion/latest_location.json",
    Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/Hermes Companion/latest_location.json",
    Path.home() / "Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/Documents/latest_location.json",
    Path.home() / "Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/latest_location.json",
    Path("/tmp/hermes_latest_location.json"),
]

ICLOUD_HEALTH_CONTAINER_PATHS: Final[List[Path]] = [
    Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/HermesCompanion/latest_health.json",
    Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/Hermes Companion/latest_health.json",
    Path.home() / "Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/Documents/latest_health.json",
    Path.home() / "Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/latest_health.json",
    Path("/tmp/hermes_latest_health.json"),
]

ICLOUD_HISTORY_CONTAINER_PATHS: Final[List[Path]] = [
    Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/HermesCompanion/location_history.json",
    Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/Hermes Companion/location_history.json",
    Path.home() / "Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/Documents/location_history.json",
    Path.home() / "Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/location_history.json",
    Path("/tmp/hermes_location_history.json"),
]


# ==============================================================================
# Typed Structures (no Any)
# ==============================================================================

class FormattedLocationPayload(TypedDict, total=False):
    status: str
    latitude: float
    longitude: float
    altitude_meters: float
    accuracy_meters: float
    horizontal_accuracy: float
    is_moving: bool
    recorded_at: Optional[str]
    age_seconds: Optional[int]
    age_human: str
    motion_activity: str
    motion_confidence: Optional[str]
    motion_timestamp: Optional[str]
    motion_age_seconds: Optional[int]
    trigger_source: str
    app_state: str
    device_name: str
    coordinates: str
    maps_link: str
    source_channel: str
    place_name: str
    place_category: str
    activity: str
    context_summary: str
    suggested_greeting: str
    is_at_known_place: bool
    known_place_id: Optional[str]
    distance_to_center_meters: Optional[float]
    still_there: bool
    still_there_status: str
    minutes_since_last_move: Optional[int]
    movement_reason: Optional[str]
    motion_fresh: bool
    is_moving_now: bool
    was_moving_at_fix: bool
    error: str


class FormattedHealthPayload(TypedDict, total=False):
    status: str
    id: Optional[str]
    recorded_at: Optional[str]
    age_seconds: Optional[int]
    age_human: str
    source_channel: str
    recovery_status: str
    step_count_today: Union[int, float]
    active_calories_today: Union[int, float]
    resting_heart_rate_bpm: Optional[Union[int, float]]
    current_heart_rate_bpm: Optional[Union[int, float]]
    heart_rate_variability_sdnn: Optional[Union[int, float]]
    sleep: Optional[Mapping[str, object]]
    workout: Optional[Mapping[str, object]]
    conversational_context: Mapping[str, object]
    suggested_openers: Sequence[object]
    error: str


class PhysicalContextPayload(TypedDict):
    location: Optional[FormattedLocationPayload]
    health: Optional[FormattedHealthPayload]
    timestamp: str


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


def _human_age(seconds: Optional[int]) -> str:
    if seconds is None:
        return "unknown"
    if seconds < 60:
        return f"{seconds}s"
    hours, minutes = divmod(seconds // 60, 60)
    if hours:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


def format_location_payload(
    data: Optional[Mapping[str, object]],
    channel_name: str = "iCloud / CloudKit",
) -> Optional[FormattedLocationPayload]:
    """Format raw location data dict to standard Hermes dictionary schema."""
    if not data or "latitude" not in data or "longitude" not in data:
        return None

    lat = _to_float(data.get("latitude"))
    lon = _to_float(data.get("longitude"))

    ts_str = str(data.get("timestamp") or data.get("recorded_at") or "") or None
    age_sec: Optional[int] = None
    if ts_str:
        try:
            rec_dt = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
            age_sec = max(0, int((datetime.now(timezone.utc) - rec_dt).total_seconds()))
        except ValueError:
            pass

    raw_acc = data.get("horizontal_accuracy", data.get("accuracy", data.get("accuracy_meters", 0.0)))
    acc = _to_float(raw_acc)

    # Real motion state from CoreMotion (independent of the GPS fix age).
    motion_activity = str(data.get("motion_activity", "unknown") or "unknown")
    motion_confidence = str(data["motion_confidence"]) if data.get("motion_confidence") else None
    motion_age_sec: Optional[int] = None
    motion_ts_str = str(data.get("motion_timestamp") or "") or None
    if motion_ts_str:
        try:
            mt = datetime.fromisoformat(motion_ts_str.replace("Z", "+00:00"))
            motion_age_sec = max(0, int((datetime.now(timezone.utc) - mt).total_seconds()))
        except ValueError:
            pass

    is_moving = motion_activity in ("walking", "running", "cycling", "automotive")
    age_human = f"{age_sec // 60}m {age_sec % 60}s ago" if (age_sec is not None and age_sec >= 60) else (f"{age_sec}s ago" if age_sec is not None else "unknown")

    payload: FormattedLocationPayload = {
        "status": "ok",
        "latitude": lat,
        "longitude": lon,
        "altitude_meters": _to_float(data.get("altitude", data.get("altitude_meters", 0.0))),
        "accuracy_meters": acc,
        "horizontal_accuracy": acc,
        "is_moving": is_moving,
        "recorded_at": ts_str,
        "age_seconds": age_sec,
        "age_human": age_human,
        "motion_activity": motion_activity,
        "motion_confidence": motion_confidence,
        "motion_timestamp": motion_ts_str,
        "motion_age_seconds": motion_age_sec,
        "trigger_source": str(data.get("source", channel_name)),
        "app_state": str(data.get("app_state", "active")),
        "device_name": str(data.get("device_name", "iPhone")),
        "coordinates": f"{lat:.6f}, {lon:.6f}",
        "maps_link": f"https://maps.apple.com/?ll={lat},{lon}&q=User+Location",
        "source_channel": channel_name,
    }

    try:
        try:
            from server.places import get_places_manager
        except ImportError:
            from places import get_places_manager  # type: ignore[import-not-found,import-untyped,no-redef]
        ctx = get_places_manager().resolve_context(
            lat,
            lon,
            is_moving=is_moving,
            age_seconds=age_sec or 0,
            motion_activity=motion_activity,
            motion_age_seconds=motion_age_sec if motion_age_sec is not None else 999999,
        )
        payload.update(ctx)  # type: ignore[typeddict-item]
    except Exception:
        pass

    # Resolve still_there consistently
    moving_now = bool(payload.get("is_moving_now", is_moving))
    is_transit = payload.get("place_category") == "transit"
    motion_fresh = bool(payload.get("motion_fresh", False))
    motion_moving = motion_activity in ("walking", "running", "cycling", "automotive")

    if moving_now or is_transit:
        payload["still_there"] = False
        payload["still_there_status"] = "no"
    elif age_sec is None:
        payload["still_there"] = False
        payload["still_there_status"] = "unconfirmed (missing or invalid timestamp)"
    elif motion_fresh and not motion_moving:
        payload["still_there"] = True
        payload["still_there_status"] = "yes"
    elif age_sec <= 1800:
        payload["still_there"] = True
        payload["still_there_status"] = "yes"
    else:
        payload["still_there"] = False
        payload["still_there_status"] = f"unconfirmed (no fresh ping in {_human_age(age_sec)})"

    return payload


def get_user_location_from_icloud() -> Optional[FormattedLocationPayload]:
    """Read the latest location directly from local iCloud container files."""
    for path in ICLOUD_CONTAINER_PATHS:
        if path.is_file():
            try:
                raw: Mapping[str, object] = json.loads(path.read_text(encoding="utf-8"))
                res = format_location_payload(raw, channel_name=f"iCloud ({path.name})")
                if res:
                    return res
            except Exception:
                continue
    return None


def get_user_location_from_sqlite(db_path: Optional[Union[str, Path]] = None) -> Optional[FormattedLocationPayload]:
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
            raw: Mapping[str, object] = dict(row)
            return format_location_payload(raw, channel_name="SQLite (local)")
    except Exception:
        pass
    return None


def get_user_location(prefer_icloud: bool = True) -> Optional[FormattedLocationPayload]:
    """
    Fetch the latest location recorded by Hermes Companion iOS.
    Reads the locally synced iCloud/CloudKit file first (zero network, no open
    ports), then the local SQLite cache. Always enriches with semantic place
    context (gym, home, transit, etc.).
    """
    data = get_user_location_from_icloud() if prefer_icloud else None

    if not data:
        data = get_user_location_from_sqlite()

    if data and "latitude" in data and "suggested_greeting" not in data:
        try:
            try:
                from server.places import get_places_manager
            except ImportError:
                from places import get_places_manager  # type: ignore[import-not-found,no-redef]
            lat = _to_float(data.get("latitude"))
            lon = _to_float(data.get("longitude"))
            moving = bool(data.get("is_moving", False))
            age = _to_int(data.get("age_seconds"))
            ctx = get_places_manager().resolve_context(lat, lon, is_moving=moving, age_seconds=age)
            data.update(ctx)  # type: ignore[typeddict-item]
        except Exception:
            pass

    return data


def add_known_place(
    name: str,
    category: str,
    activity: str,
    latitude: Union[float, str],
    longitude: Union[float, str],
    radius_meters: Union[float, str] = 150.0,
    notes: str = "",
) -> Mapping[str, object]:
    """Register a known place such as home, work, or a gym."""
    try:
        from server.places import get_places_manager
    except ImportError:
        from places import get_places_manager  # type: ignore[import-not-found,no-redef]
    return get_places_manager().add_place(
        name=name,
        category=category,
        activity=activity,
        latitude=_to_float(latitude),
        longitude=_to_float(longitude),
        radius_meters=_to_float(radius_meters, 150.0),
        notes=notes,
    ).to_dict()


def list_known_places() -> List[Mapping[str, object]]:
    """List all registered known places."""
    try:
        from server.places import get_places_manager
    except ImportError:
        from places import get_places_manager  # type: ignore[import-not-found,no-redef]
    return [p.to_dict() for p in get_places_manager().list_places()]


def format_health_payload(
    data: Optional[Mapping[str, object]],
    channel_name: str = "iCloud / CloudKit",
) -> Optional[FormattedHealthPayload]:
    """Format raw health data dict to standard Hermes dictionary schema."""
    if not data or not isinstance(data, Mapping):
        return None

    ts_str = str(data.get("timestamp") or data.get("recorded_at") or "") or None
    age_sec: Optional[int] = None
    if ts_str:
        try:
            rec_dt = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
            age_sec = max(0, int((datetime.now(timezone.utc) - rec_dt).total_seconds()))
        except ValueError:
            pass

    age_human = f"{age_sec // 60}m {age_sec % 60}s ago" if (age_sec is not None and age_sec >= 60) else (f"{age_sec}s ago" if age_sec is not None else "unknown")
    raw_ctx = data.get("conversational_context")
    ctx: Mapping[str, object] = raw_ctx if isinstance(raw_ctx, Mapping) else {}

    openers = data.get("suggested_openers")
    if not openers and isinstance(ctx.get("suggestedOpeners"), Sequence):
        openers = ctx["suggestedOpeners"]  # type: ignore[assignment]

    raw_sleep = data.get("sleep")
    sleep = raw_sleep if isinstance(raw_sleep, Mapping) else None
    raw_workout = data.get("workout")
    workout = raw_workout if isinstance(raw_workout, Mapping) else None

    payload: FormattedHealthPayload = {
        "status": "ok",
        "id": str(data["id"]) if data.get("id") else None,
        "recorded_at": ts_str,
        "age_seconds": age_sec,
        "age_human": age_human,
        "source_channel": channel_name,
        "recovery_status": str(data.get("recovery_status", "unknown")),
        "step_count_today": _to_float(data.get("step_count_today")),
        "active_calories_today": _to_float(data.get("active_calories_today")),
        "resting_heart_rate_bpm": _to_float(data["resting_heart_rate_bpm"]) if data.get("resting_heart_rate_bpm") is not None else None,
        "current_heart_rate_bpm": _to_float(data["current_heart_rate_bpm"]) if data.get("current_heart_rate_bpm") is not None else None,
        "heart_rate_variability_sdnn": _to_float(data["heart_rate_variability_sdnn"]) if data.get("heart_rate_variability_sdnn") is not None else None,
        "sleep": sleep,
        "workout": workout,
        "conversational_context": ctx,
        "suggested_openers": list(openers) if isinstance(openers, Sequence) else [],
    }
    return payload


def get_user_health_from_icloud() -> Optional[FormattedHealthPayload]:
    """Read the latest health snapshot directly from local iCloud container files."""
    for path in ICLOUD_HEALTH_CONTAINER_PATHS:
        if path.is_file():
            try:
                raw: Mapping[str, object] = json.loads(path.read_text(encoding="utf-8"))
                res = format_health_payload(raw, channel_name=f"iCloud ({path.name})")
                if res:
                    return res
            except Exception:
                continue
    return None


def get_location_history_from_icloud(limit: int = 100) -> List[Mapping[str, object]]:
    """Read rolling location history directly from local iCloud container files."""
    for path in ICLOUD_HISTORY_CONTAINER_PATHS:
        if path.is_file():
            try:
                raw = json.loads(path.read_text(encoding="utf-8"))
                records = raw.get("records") if isinstance(raw, dict) else raw
                if isinstance(records, list):
                    return records[-limit:] if limit else records
            except Exception:
                continue
    return []


def get_user_health_from_sqlite(db_path: Optional[Union[str, Path]] = None) -> Optional[FormattedHealthPayload]:
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
            raw: Mapping[str, object] = dict(row)
            parsed: Mapping[str, object] = {}
            if raw.get("raw_payload"):
                try:
                    loaded = json.loads(str(raw["raw_payload"]))
                    if isinstance(loaded, Mapping):
                        parsed = loaded
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
                        "formatted_duration": f"{_to_int(raw['sleep_duration_minutes']) // 60}h {_to_int(raw['sleep_duration_minutes']) % 60}m",
                        "quality_rating": raw["sleep_quality"],
                        "summary": raw["sleep_summary"]
                    } if _to_float(raw.get("sleep_duration_minutes")) > 0 else None,
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


def get_user_health(prefer_icloud: bool = True) -> Optional[FormattedHealthPayload]:
    """
    Fetch the latest Apple Health snapshot from Hermes Companion.
    Reads the locally synced iCloud/CloudKit file first (zero network), then the
    local SQLite cache.
    """
    data = get_user_health_from_icloud() if prefer_icloud else None

    if not data:
        data = get_user_health_from_sqlite()

    return data


def get_user_physical_context(prefer_icloud: bool = True) -> PhysicalContextPayload:
    """
    Unified physical context combining physical location (e.g. at the gym, at home)
    and Apple Health telemetry (sleep quality, active workout, post-workout recovery, vitals).
    """
    loc = get_user_location(prefer_icloud=prefer_icloud)
    health = get_user_health(prefer_icloud=prefer_icloud)
    return {
        "location": loc,
        "health": health,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
