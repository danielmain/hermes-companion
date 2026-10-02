#!/usr/bin/env python3
"""Read Hermes Companion iPhone telemetry from the local iCloud folder.

The iOS app writes latest_location.json and latest_health.json into its
iCloud container. macOS materialises those files on disk. This script turns
them into the place, motion, sleep, and workout facts the Hermes skill speaks
from. It uses the Python standard library only.

A location file exists only after GPSPersistDecision accepts a move. Its
timestamp is the last accepted move. A growing age at a known place means the
person is still there.

Usage:
  python3 companion.py
  python3 companion.py --json
  python3 companion.py --health
  python3 companion.py --context
  python3 companion.py --list
  python3 companion.py --add --name Home --category home --lat 52.52 --lon 13.40
  python3 companion.py --remove home
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sqlite3
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

MOTION_FRESH_SECONDS = 300
LONG_STAY_SECONDS = 600
MOVING_ACTIVITIES = ("walking", "running", "cycling", "automotive")
MOTION_LABELS = {
    "walking": "walking",
    "running": "running",
    "cycling": "cycling",
    "automotive": "driving",
}
CATEGORIES = ("home", "work", "gym", "cafe", "outdoors", "general")

ICLOUD_DIRS = (
    Path.home() / "Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/Documents",
    Path.home() / "Library/Mobile Documents/iCloud~com~hermes~HermesCompanion",
    Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/HermesCompanion",
    Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/Hermes Companion",
)


def log(level: str, message: str) -> None:
    print(f"{level} hermes-companion: {message}", file=sys.stderr)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def parse_utc(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def age_seconds(value: Optional[str], now: datetime) -> Optional[int]:
    recorded = parse_utc(value)
    if recorded is None:
        return None
    return max(0, int((now - recorded).total_seconds()))


def human_age(seconds: Optional[int]) -> str:
    if seconds is None:
        return "unknown"
    if seconds < 60:
        return f"{seconds}s"
    hours, minutes = divmod(seconds // 60, 60)
    if hours:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


def haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius = 6_371_000.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lon2 - lon1)
    a = math.sin(d_phi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2.0) ** 2
    return radius * 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))


def slug(name: str) -> str:
    cleaned = "".join(ch.lower() if ch.isalnum() else "_" for ch in name.strip())
    while "__" in cleaned:
        cleaned = cleaned.replace("__", "_")
    return cleaned.strip("_") or "place"


def expand(path: str) -> Path:
    return Path(path).expanduser()


def icloud_directories(override: Optional[str]) -> List[Path]:
    if override:
        return [expand(override)]
    env = os.environ.get("HERMES_COMPANION_ICLOUD_DIR", "").strip()
    if env:
        return [expand(env)]
    return list(ICLOUD_DIRS)


def read_json_file(path: Path) -> Optional[Dict[str, Any]]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except OSError as exc:
        log("ERROR", f"could not read {path}: {exc}")
        return None
    except json.JSONDecodeError as exc:
        log("ERROR", f"invalid JSON in {path}: {exc}")
        return None
    if not isinstance(data, dict):
        log("ERROR", f"{path} is not a JSON object")
        return None
    return data


def first_reading(directories: Sequence[Path], filename: str) -> tuple[Optional[Dict[str, Any]], Optional[Path]]:
    seen = False
    for directory in directories:
        path = directory / filename
        if not path.is_file():
            continue
        seen = True
        data = read_json_file(path)
        if data is not None:
            return data, path
    if not seen:
        log("WARN", f"{filename} is not in the iCloud container yet")
    return None, None


def default_places_file() -> Path:
    env = os.environ.get("HERMES_COMPANION_PLACES", "").strip()
    if env:
        return expand(env)
    hermes_home = os.environ.get("HERMES_HOME", "").strip()
    if hermes_home:
        profile_places = expand(hermes_home) / "state" / "places.json"
        if profile_places.is_file() or (expand(hermes_home) / "state").is_dir():
            return profile_places
    profiles = Path.home() / ".hermes" / "profiles"
    found = sorted(profiles.glob("*/state/places.json")) if profiles.is_dir() else []
    if len(found) == 1:
        return found[0]
    return Path.home() / ".hermes" / "hermes-companion" / "places.json"


def load_places(path: Path) -> List[Dict[str, Any]]:
    if not path.is_file():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        log("ERROR", f"could not read places {path}: {exc}")
        return []
    if not isinstance(data, list):
        log("ERROR", f"places file {path} must be a JSON list")
        return []
    return [item for item in data if isinstance(item, dict)]


def save_places(path: Path, places: Sequence[Dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(list(places), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    log("INFO", f"wrote {len(places)} place(s) to {path}")


def match_place(latitude: float, longitude: float, places: Sequence[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    best: Optional[Dict[str, Any]] = None
    best_distance = float("inf")
    for place in places:
        try:
            distance = haversine_meters(latitude, longitude, float(place["latitude"]), float(place["longitude"]))
            radius = float(place.get("radius_meters") or 150)
        except (KeyError, TypeError, ValueError):
            continue
        if distance <= radius and distance < best_distance:
            best = place
            best_distance = distance
    if best is None:
        return None
    return {**best, "distance_meters": round(best_distance, 1)}


def resolve_location(
    raw: Dict[str, Any],
    places: Sequence[Dict[str, Any]],
    now: datetime,
    source: str,
) -> Dict[str, Any]:
    latitude = float(raw["latitude"])
    longitude = float(raw["longitude"])
    recorded_at = raw.get("timestamp") or raw.get("recorded_at")
    gps_age = age_seconds(recorded_at, now) or 0
    speed_mps = float(raw.get("speed_mps", raw.get("speed", -1.0)) or -1.0)
    speed_kmh = round(speed_mps * 3.6, 1) if speed_mps > 0 else 0.0
    motion = str(raw.get("motion_activity") or "unknown")
    motion_age = age_seconds(raw.get("motion_timestamp"), now)
    motion_age_value = motion_age if motion_age is not None else 999_999
    valid_motion = motion in ("stationary", *MOVING_ACTIVITIES)
    motion_fresh = valid_motion and motion_age_value <= MOTION_FRESH_SECONDS
    motion_moving = motion in MOVING_ACTIVITIES
    long_stay = gps_age > LONG_STAY_SECONDS
    fix_moving = speed_kmh > 3.0
    moving_now = motion_moving if motion_fresh else (fix_moving and not long_stay)
    known = match_place(latitude, longitude, places)
    label = MOTION_LABELS.get(motion)
    minutes = gps_age // 60

    if moving_now and known and label in ("walking", "running", "cycling"):
        place_name = str(known.get("name") or "Known place")
        category = str(known.get("category") or "general")
        activity = label
        at_known = True
    elif moving_now:
        place_name = "In Transit"
        category = "transit"
        activity = motion if motion in MOVING_ACTIVITIES else "moving"
        at_known = False
        known = None
    elif known:
        place_name = str(known.get("name") or "Known place")
        category = str(known.get("category") or "general")
        activity = str(known.get("activity") or category)
        at_known = True
    else:
        place_name = "Unlisted place"
        category = "unlisted"
        activity = "unlisted"
        at_known = False

    accuracy = raw.get("horizontal_accuracy", raw.get("accuracy"))
    if at_known:
        if motion_fresh and not motion_moving:
            still_there = True
            still_there_txt = "yes"
        elif gps_age <= 1800:
            still_there = True
            still_there_txt = "yes"
        else:
            still_there = False
            still_there_txt = f"unconfirmed (no fresh ping in {human_age(gps_age)})"
    else:
        still_there = True
        still_there_txt = "yes"

    return {
        "status": "ok",
        "source_file": source,
        "latitude": latitude,
        "longitude": longitude,
        "coordinates": f"{latitude:.6f}, {longitude:.6f}",
        "accuracy_meters": accuracy,
        "recorded_at": recorded_at,
        "age_seconds": gps_age,
        "age_human": human_age(gps_age),
        "minutes_since_last_move": minutes,
        "movement_reason": raw.get("movement_reason"),
        "is_stale": long_stay,
        "still_there": still_there,
        "still_there_status": still_there_txt,
        "place_name": place_name,
        "place_category": category,
        "activity": activity,
        "is_at_known_place": at_known,
        "known_place_id": known.get("id") if known else None,
        "distance_to_center_meters": known.get("distance_meters") if known else None,
        "motion_activity": motion if valid_motion else "unknown",
        "motion_confidence": raw.get("motion_confidence"),
        "motion_age_seconds": None if motion_age is None else motion_age,
        "motion_fresh": motion_fresh,
        "is_moving_now": moving_now,
        "speed_kmh": speed_kmh,
        "trigger_source": raw.get("source"),
        "app_state": raw.get("app_state"),
    }


PROSE_HEALTH_KEYS = ("sleep_insight", "workout_insight", "nutrition_reminder", "suggested_openers", "suggestedOpeners")


def health_facts(raw: Dict[str, Any]) -> Dict[str, Any]:
    """Numbers and codes only. English sentences in older files are not forwarded."""
    ctx = raw.get("conversational_context") if isinstance(raw.get("conversational_context"), dict) else {}
    leftover = [key for key in PROSE_HEALTH_KEYS if ctx.get(key) or raw.get(key)]
    if leftover:
        log("INFO", "ignoring health prose fields: " + ", ".join(leftover))
    sleep = raw.get("sleep") if isinstance(raw.get("sleep"), dict) else None
    workout = raw.get("workout") if isinstance(raw.get("workout"), dict) else None
    return {
        "sleep": None if sleep is None else {
            "formatted_duration": sleep.get("formatted_duration"),
            "total_sleep_minutes": sleep.get("total_sleep_minutes"),
            "quality_rating": sleep.get("quality_rating"),
        },
        "workout": None if workout is None else {
            "workout_type": workout.get("workout_type"),
            "is_currently_active": workout.get("is_currently_active"),
            "phase": workout.get("phase"),
            "duration_minutes": workout.get("duration_minutes"),
            "minutes_since_completion": workout.get("minutes_since_completion"),
            "active_calories": workout.get("active_calories"),
        },
    }


def resolve_health(raw: Dict[str, Any], now: datetime, source: str) -> Dict[str, Any]:
    recorded_at = raw.get("timestamp") or raw.get("recorded_at")
    seconds = age_seconds(recorded_at, now) or 0
    facts = health_facts(raw)
    return {
        "status": "ok",
        "source_file": source,
        "recorded_at": recorded_at,
        "age_seconds": seconds,
        "age_human": human_age(seconds),
        "recovery_status": raw.get("recovery_status", "unknown"),
        "step_count_today": raw.get("step_count_today", 0),
        "active_calories_today": raw.get("active_calories_today", 0),
        "resting_heart_rate_bpm": raw.get("resting_heart_rate_bpm"),
        "current_heart_rate_bpm": raw.get("current_heart_rate_bpm"),
        "heart_rate_variability_sdnn": raw.get("heart_rate_variability_sdnn"),
        "sleep": facts["sleep"],
        "workout": facts["workout"],
    }


def format_location(loc: Dict[str, Any]) -> str:
    motion_age = loc.get("motion_age_seconds")
    motion_age_text = "none" if motion_age is None else str(motion_age)
    still_there_txt = loc.get("still_there_status") or ("yes" if loc.get("still_there") else "no")
    lines = [
        "facts_only: reply in the user's language; do not quote this block",
        f"place_name: {loc['place_name']}",
        f"place_category: {loc['place_category']}",
        f"still_there: {still_there_txt}",
        f"minutes_since_last_move: {loc['minutes_since_last_move']}",
        f"movement_reason: {loc.get('movement_reason') or 'absent'}",
        f"motion_activity: {loc['motion_activity']}",
        f"motion_fresh: {'yes' if loc.get('motion_fresh') else 'no'}",
        f"motion_age_seconds: {motion_age_text}",
        f"is_moving_now: {'yes' if loc['is_moving_now'] else 'no'}",
        f"recorded_at: {loc.get('recorded_at')}",
        f"age_seconds: {loc['age_seconds']}",
        f"coordinates: {loc['coordinates']}",
        f"source: {loc['source_file']}",
    ]
    if loc.get("arrived_at"):
        lines.append(f"arrived_at: {loc['arrived_at']}")
    if loc.get("dwell_time"):
        lines.append(f"dwell_time: {loc['dwell_time']}")
    if loc.get("previous_place"):
        lines.append(f"previous_place: {loc['previous_place']}")
    if loc.get("telemetry_gap"):
        lines.append(f"telemetry_gap: {loc['telemetry_gap']}")
    return "\n".join(lines)


def format_health(health: Dict[str, Any]) -> str:
    lines = [
        "facts_only: reply in the user's language; do not quote this block",
        f"recovery_status: {health.get('recovery_status')}",
        f"recorded_at: {health.get('recorded_at')}",
        f"age_seconds: {health.get('age_seconds')}",
    ]
    sleep = health.get("sleep") or None
    if isinstance(sleep, dict):
        lines.append(f"sleep_duration: {sleep.get('formatted_duration') or sleep.get('total_sleep_minutes') or 'unknown'}")
        lines.append(f"sleep_quality: {sleep.get('quality_rating') or 'unknown'}")
    else:
        lines.append("sleep_duration: none")
    workout = health.get("workout") or None
    if isinstance(workout, dict):
        lines.append(f"workout_type: {workout.get('workout_type') or 'unknown'}")
        lines.append(f"workout_active: {'yes' if workout.get('is_currently_active') else 'no'}")
        lines.append(f"workout_phase: {workout.get('phase') or 'unknown'}")
        lines.append(f"workout_duration_minutes: {workout.get('duration_minutes')}")
        if workout.get("minutes_since_completion") is not None:
            lines.append(f"minutes_since_workout: {workout.get('minutes_since_completion')}")
    else:
        lines.append("workout_type: none")
    lines.append(f"steps_today: {health.get('step_count_today') or 0}")
    lines.append(f"active_calories_today: {int(float(health.get('active_calories_today') or 0))}")
    if health.get("resting_heart_rate_bpm") is not None:
        lines.append(f"resting_heart_rate_bpm: {health['resting_heart_rate_bpm']}")
    if health.get("heart_rate_variability_sdnn") is not None:
        lines.append(f"hrv_sdnn_ms: {health['heart_rate_variability_sdnn']}")
    lines.append(f"source: {health['source_file']}")
    return "\n".join(lines)


def read_history(directories: Sequence[Path]) -> tuple[List[Dict[str, Any]], Optional[Path]]:
    raw, path = first_reading(directories, "location_history.json")
    if raw is None or path is None:
        return [], None
    records = raw.get("records") if isinstance(raw, dict) else raw
    if not isinstance(records, list):
        return [], path
    valid: List[Dict[str, Any]] = []
    for item in records:
        if isinstance(item, dict) and "latitude" in item and "longitude" in item:
            valid.append(item)
    valid.sort(key=lambda r: str(r.get("timestamp") or r.get("recorded_at") or ""))
    return valid, path


def parse_since(since_str: Optional[str], now: datetime) -> Optional[datetime]:
    if not since_str:
        return None
    val = since_str.strip().lower()
    if val == "today":
        return datetime(now.year, now.month, now.day, tzinfo=timezone.utc)
    if val.endswith("h"):
        try:
            return now - timedelta(hours=float(val[:-1]))
        except ValueError:
            pass
    if val.endswith("d"):
        try:
            return now - timedelta(days=float(val[:-1]))
        except ValueError:
            pass
    if val.endswith("m"):
        try:
            return now - timedelta(minutes=float(val[:-1]))
        except ValueError:
            pass
    return parse_utc(since_str)


def build_timeline(
    records: Sequence[Dict[str, Any]],
    places: Sequence[Dict[str, Any]],
    now: datetime,
    since: Optional[datetime] = None,
) -> Dict[str, Any]:
    if since:
        records = [r for r in records if (parse_utc(r.get("timestamp") or r.get("recorded_at")) or now) >= since]

    if not records:
        return {"events": [], "count": 0, "status": "no_records"}

    events: List[Dict[str, Any]] = []
    current_stay: Optional[Dict[str, Any]] = None
    last_record: Optional[Dict[str, Any]] = None

    for r in records:
        lat = float(r["latitude"])
        lon = float(r["longitude"])
        ts_str = r.get("timestamp") or r.get("recorded_at")
        ts = parse_utc(ts_str) or now
        motion = str(r.get("motion_activity") or "unknown")
        known = match_place(lat, lon, places)

        gap_detected = False
        gap_minutes = 0
        if last_record:
            last_ts = parse_utc(last_record.get("timestamp") or last_record.get("recorded_at")) or now
            delta_sec = (ts - last_ts).total_seconds()
            dist = haversine_meters(float(last_record["latitude"]), float(last_record["longitude"]), lat, lon)
            if delta_sec > 1800 and dist > 100:
                gap_detected = True
                gap_minutes = int(delta_sec // 60)

        is_place = known is not None
        place_name = known["name"] if known else "Unlisted place"
        place_cat = known["category"] if known else "unlisted"

        if is_place:
            if current_stay and current_stay["place_name"] == place_name:
                current_stay["departed_at"] = ts_str
                current_stay["records_count"] += 1
                current_stay["last_timestamp"] = ts
                dwell_sec = max(0, int((ts - current_stay["start_timestamp"]).total_seconds()))
                current_stay["dwell_minutes"] = dwell_sec // 60
                current_stay["dwell_human"] = human_age(dwell_sec)
                if gap_detected:
                    current_stay["telemetry_gap_before"] = f"silent for {gap_minutes}m before this point"
            else:
                if current_stay:
                    events.append(current_stay)
                if last_record:
                    last_known = match_place(float(last_record["latitude"]), float(last_record["longitude"]), places)
                    from_name = last_known["name"] if last_known else "Transit"
                    dist = haversine_meters(float(last_record["latitude"]), float(last_record["longitude"]), lat, lon)
                    if from_name != place_name and dist > 50:
                        transit_event = {
                            "type": "transit",
                            "from_place": from_name,
                            "to_place": place_name,
                            "started_at": last_record.get("timestamp") or last_record.get("recorded_at"),
                            "ended_at": ts_str,
                            "distance_meters": round(dist, 1),
                            "duration_minutes": max(1, int((ts - (parse_utc(last_record.get("timestamp") or last_record.get("recorded_at")) or ts)).total_seconds() // 60)),
                            "activity": motion if motion in MOVING_ACTIVITIES else "moving",
                            "telemetry_gap": f"silent for {gap_minutes}m during transit" if gap_detected else None,
                        }
                        events.append(transit_event)

                current_stay = {
                    "type": "stay",
                    "place_name": place_name,
                    "place_category": place_cat,
                    "arrived_at": ts_str,
                    "departed_at": ts_str,
                    "start_timestamp": ts,
                    "last_timestamp": ts,
                    "dwell_minutes": 0,
                    "dwell_human": "just arrived",
                    "records_count": 1,
                    "is_current": False,
                    "telemetry_gap_before": f"silent for {gap_minutes}m before arrival" if gap_detected else None,
                }
        else:
            if current_stay and current_stay.get("type") == "stay":
                events.append(current_stay)
                current_stay = None

            dist = haversine_meters(float(last_record["latitude"]), float(last_record["longitude"]), lat, lon) if last_record else 0
            if not current_stay:
                current_stay = {
                    "type": "transit",
                    "place_name": "In Transit",
                    "place_category": "transit",
                    "from_place": last_record.get("place_name", "Previous place") if last_record else "Unknown",
                    "to_place": "Moving",
                    "started_at": ts_str,
                    "ended_at": ts_str,
                    "start_timestamp": ts,
                    "last_timestamp": ts,
                    "distance_meters": round(dist, 1),
                    "duration_minutes": 0,
                    "activity": motion if motion in MOVING_ACTIVITIES else "moving",
                    "is_current": False,
                    "telemetry_gap": f"silent for {gap_minutes}m" if gap_detected else None,
                }
            else:
                current_stay["ended_at"] = ts_str
                current_stay["last_timestamp"] = ts
                current_stay["distance_meters"] = round(current_stay.get("distance_meters", 0) + dist, 1)
                current_stay["duration_minutes"] = max(1, int((ts - current_stay["start_timestamp"]).total_seconds() // 60))

        last_record = {**r, "place_name": place_name}

    if current_stay:
        current_stay["is_current"] = True
        if current_stay["type"] == "stay":
            dwell_now = max(0, int((now - current_stay["start_timestamp"]).total_seconds()))
            current_stay["dwell_minutes"] = dwell_now // 60
            current_stay["dwell_human"] = human_age(dwell_now)
            current_stay["departed_at"] = None
        events.append(current_stay)

    clean_events = []
    for ev in events:
        ev_copy = dict(ev)
        ev_copy.pop("start_timestamp", None)
        ev_copy.pop("last_timestamp", None)
        clean_events.append(ev_copy)

    latest = records[-1]
    latest_lat = float(latest["latitude"])
    latest_lon = float(latest["longitude"])
    latest_known = match_place(latest_lat, latest_lon, places)
    latest_ts = parse_utc(latest.get("timestamp") or latest.get("recorded_at")) or now
    age_now = int((now - latest_ts).total_seconds())

    return {
        "status": "ok",
        "total_records": len(records),
        "events_count": len(clean_events),
        "current_place": latest_known["name"] if latest_known else "Unlisted place",
        "current_category": latest_known["category"] if latest_known else "unlisted",
        "current_motion": str(latest.get("motion_activity") or "unknown"),
        "latest_recorded_at": latest.get("timestamp") or latest.get("recorded_at"),
        "latest_age_seconds": age_now,
        "latest_age_human": human_age(age_now),
        "events": clean_events,
    }


def query_history_sqlite(
    records: Sequence[Dict[str, Any]],
    places: Sequence[Dict[str, Any]],
    sql_query: str,
) -> List[Dict[str, Any]]:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE locations (
            id TEXT,
            timestamp TEXT,
            latitude REAL,
            longitude REAL,
            altitude REAL,
            horizontal_accuracy REAL,
            speed_mps REAL,
            course REAL,
            source TEXT,
            app_state TEXT,
            motion_activity TEXT,
            motion_confidence TEXT,
            motion_timestamp TEXT,
            movement_reason TEXT,
            device_name TEXT,
            place_name TEXT,
            place_category TEXT
        )
        """
    )
    for r in records:
        lat = float(r.get("latitude") or 0.0)
        lon = float(r.get("longitude") or 0.0)
        known = match_place(lat, lon, places)
        p_name = known["name"] if known else None
        p_cat = known["category"] if known else None
        cur.execute(
            """
            INSERT INTO locations VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                str(r.get("id", "")),
                str(r.get("timestamp") or r.get("recorded_at") or ""),
                lat,
                lon,
                float(r.get("altitude") or 0.0),
                float(r.get("horizontal_accuracy") or r.get("accuracy") or 0.0),
                float(r.get("speed_mps") or r.get("speed") or -1.0),
                float(r.get("course") or -1.0),
                str(r.get("source") or ""),
                str(r.get("app_state") or ""),
                str(r.get("motion_activity") or "unknown"),
                str(r.get("motion_confidence") or ""),
                str(r.get("motion_timestamp") or ""),
                str(r.get("movement_reason") or ""),
                str(r.get("device_name") or ""),
                p_name,
                p_cat,
            ),
        )
    conn.commit()
    cur.execute(sql_query)
    rows = cur.fetchall()
    results = [dict(row) for row in rows]
    conn.close()
    return results


def format_timeline(timeline: Dict[str, Any]) -> str:
    lines = [
        "facts_only: reply in the user's language; do not quote this block",
        f"current_place: {timeline.get('current_place', 'unknown')}",
        f"current_motion: {timeline.get('current_motion', 'unknown')}",
        f"latest_fix_age: {timeline.get('latest_age_human', 'unknown')}",
        f"events_count: {timeline.get('events_count', 0)}",
        "timeline_events:",
    ]
    events = timeline.get("events", [])
    if not events:
        lines.append("  (no events in this time window)")
    for ev in events:
        ev_type = ev.get("type", "event")
        if ev_type == "stay":
            curr_tag = " [current]" if ev.get("is_current") else ""
            dep = f" -> departed {ev.get('departed_at')}" if ev.get("departed_at") else " -> now"
            gap = f" [{ev['telemetry_gap_before']}]" if ev.get("telemetry_gap_before") else ""
            lines.append(
                f"  • stay: {ev['place_name']} ({ev.get('place_category', 'general')}) | arrived {ev.get('arrived_at')}{dep} | dwell: {ev.get('dwell_human')}{curr_tag}{gap}"
            )
        elif ev_type == "transit":
            gap = f" [{ev['telemetry_gap']}]" if ev.get("telemetry_gap") else ""
            dist = f"~{int(ev.get('distance_meters', 0))}m" if ev.get("distance_meters") else "transit"
            lines.append(
                f"  • transit: {ev.get('activity', 'moving')} {dist} from {ev.get('from_place')} to {ev.get('to_place')} | {ev.get('started_at')} -> {ev.get('ended_at')} ({ev.get('duration_minutes')}m){gap}"
            )
        else:
            lines.append(f"  • {ev_type}: {ev}")
    return "\n".join(lines)


def emit(payload: Dict[str, Any], as_json: bool, text: str) -> int:
    if as_json:
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    else:
        print(text)
    return 0


def command_where(args: argparse.Namespace, now: datetime) -> int:
    directories = icloud_directories(args.icloud_dir)
    raw, path = first_reading(directories, "latest_location.json")
    if raw is None or path is None or "latitude" not in raw or "longitude" not in raw:
        print("No accepted location file from the iPhone yet.")
        return 0
    places = load_places(args.places)
    loc = resolve_location(raw, places, now, str(path))

    # Enrich with history context if location_history.json is available
    history_records, _ = read_history(directories)
    if history_records:
        timeline = build_timeline(history_records, places, now)
        events = timeline.get("events", [])
        if events:
            current_ev = events[-1] if events[-1].get("is_current") else None
            if current_ev and current_ev.get("type") == "stay":
                if current_ev.get("arrived_at"):
                    loc["arrived_at"] = current_ev["arrived_at"]
                if current_ev.get("dwell_human"):
                    loc["dwell_time"] = current_ev["dwell_human"]
                if current_ev.get("telemetry_gap_before"):
                    loc["telemetry_gap"] = current_ev["telemetry_gap_before"]
            stays = [ev for ev in events if ev.get("type") == "stay"]
            if len(stays) >= 2 and stays[-1].get("is_current"):
                prev = stays[-2]
                loc["previous_place"] = f"{prev.get('place_name')} (departed {prev.get('departed_at')})"

    return emit(loc, args.json, format_location(loc))


def command_timeline(args: argparse.Namespace, now: datetime) -> int:
    directories = icloud_directories(args.icloud_dir)
    history_records, path = read_history(directories)
    if not history_records or path is None:
        print("No location history file from the iPhone yet.")
        return 0
    places = load_places(args.places)
    since_dt = parse_since(args.since, now)

    if args.sql:
        results = query_history_sqlite(history_records, places, args.sql)
        payload = {"count": len(results), "query": args.sql, "results": results}
        if args.json:
            print(json.dumps(payload, indent=2, ensure_ascii=False))
            return 0
        if not results:
            print("No rows returned by query.")
            return 0
        headers = list(results[0].keys())
        print(f"SQL Results ({len(results)} rows):")
        print(" | ".join(headers))
        for row in results:
            print(" | ".join(str(row.get(h, "")) for h in headers))
        return 0

    timeline = build_timeline(history_records, places, now, since=since_dt)
    timeline["source_file"] = str(path)
    return emit(timeline, args.json, format_timeline(timeline))


def command_health(args: argparse.Namespace, now: datetime) -> int:
    raw, path = first_reading(icloud_directories(args.icloud_dir), "latest_health.json")
    if raw is None or path is None:
        print("No health snapshot from the iPhone yet.")
        return 0
    health = resolve_health(raw, now, str(path))
    return emit(health, args.json, format_health(health))


def command_context(args: argparse.Namespace, now: datetime) -> int:
    directories = icloud_directories(args.icloud_dir)
    loc_raw, loc_path = first_reading(directories, "latest_location.json")
    health_raw, health_path = first_reading(directories, "latest_health.json")
    loc = None
    if loc_raw and loc_path and "latitude" in loc_raw:
        loc = resolve_location(loc_raw, load_places(args.places), now, str(loc_path))
    health = resolve_health(health_raw, now, str(health_path)) if health_raw and health_path else None
    payload = {"location": loc, "health": health}
    if args.json:
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return 0
    parts = []
    parts.append(format_location(loc) if loc else "facts_only: reply in the user's language; do not quote this block\nplace_name: unavailable")
    parts.append(format_health(health) if health else "facts_only: reply in the user's language; do not quote this block\nrecovery_status: unavailable")
    print("\n\n".join(parts))
    return 0


def command_list(args: argparse.Namespace) -> int:
    places = load_places(args.places)
    if args.json:
        print(json.dumps(places, indent=2, ensure_ascii=False))
        return 0
    if not places:
        print(f"No places in {args.places}")
        return 0
    print(f"Known places ({len(places)}) in {args.places}:")
    for place in places:
        print(
            "• [{id}] {name} ({category}) — {activity} | {lat:.5f}, {lon:.5f} (±{radius:.0f} m)".format(
                id=place.get("id", "?"),
                name=place.get("name", "Unnamed"),
                category=place.get("category", "general"),
                activity=place.get("activity") or f"at {place.get('name', 'place')}",
                lat=float(place.get("latitude") or 0),
                lon=float(place.get("longitude") or 0),
                radius=float(place.get("radius_meters") or 150),
            )
        )
    return 0


def command_add(args: argparse.Namespace) -> int:
    if not args.name or args.lat is None or args.lon is None:
        log("ERROR", "--add requires --name, --lat, and --lon")
        return 2
    category = (args.category or "general").lower()
    if category not in CATEGORIES:
        log("ERROR", f"category must be one of: {', '.join(CATEGORIES)}")
        return 2
    places = load_places(args.places)
    place_id = slug(args.name)
    record = {
        "id": place_id,
        "name": args.name,
        "category": category,
        "activity": args.activity or f"at {args.name}",
        "latitude": args.lat,
        "longitude": args.lon,
        "radius_meters": args.radius,
        "notes": args.notes or "",
    }
    replaced = False
    updated: List[Dict[str, Any]] = []
    for place in places:
        if place.get("id") == place_id or place.get("name") == args.name:
            updated.append(record)
            replaced = True
        else:
            updated.append(place)
    if not replaced:
        updated.append(record)
    save_places(args.places, updated)
    print(f"{'Updated' if replaced else 'Added'} {args.name} [{place_id}]")
    return 0


def command_remove(args: argparse.Namespace) -> int:
    if not args.remove:
        log("ERROR", "--remove requires a place id or name")
        return 2
    target = args.remove.lower()
    places = load_places(args.places)
    kept = [place for place in places if str(place.get("id", "")).lower() != target and str(place.get("name", "")).lower() != target]
    if len(kept) == len(places):
        log("WARN", f"no place named {args.remove}")
        return 0
    save_places(args.places, kept)
    print(f"Removed {args.remove}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Read Hermes Companion location and health from iCloud")
    parser.add_argument("--json", action="store_true", help="Print the raw facts as JSON")
    parser.add_argument("--timeline", action="store_true", help="Print chronological timeline of visits, stays, and movements")
    parser.add_argument("--history", action="store_true", help="Alias for --timeline")
    parser.add_argument("--since", help="Filter history events: 'today', '24h', '7d', '60m', or ISO-8601 UTC")
    parser.add_argument("--sql", help="Run an in-memory SQL query against history records")
    parser.add_argument("--health", action="store_true", help="Print the Apple Health snapshot")
    parser.add_argument("--context", action="store_true", help="Print place and health together")
    parser.add_argument("--list", action="store_true", help="List known places")
    parser.add_argument("--add", action="store_true", help="Save a known place")
    parser.add_argument("--remove", metavar="ID", help="Remove a place by id or name")
    parser.add_argument("--places", type=Path, help="Places JSON file")
    parser.add_argument("--icloud-dir", help="Directory that contains the latest_*.json files")
    parser.add_argument("--name")
    parser.add_argument("--category", default="general")
    parser.add_argument("--activity")
    parser.add_argument("--lat", type=float)
    parser.add_argument("--lon", type=float)
    parser.add_argument("--radius", type=float, default=150.0)
    parser.add_argument("--notes", default="")
    return parser


def main(argv: Optional[Sequence[str]] = None, now: Optional[datetime] = None) -> int:
    args = build_parser().parse_args(argv)
    if args.places is None:
        args.places = default_places_file()
    else:
        args.places = expand(str(args.places))
    moment = now or utcnow()
    if args.add:
        return command_add(args)
    if args.remove:
        return command_remove(args)
    if args.list:
        return command_list(args)
    if args.timeline or args.history or args.sql:
        return command_timeline(args, moment)
    if args.context:
        return command_context(args, moment)
    if args.health:
        return command_health(args, moment)
    return command_where(args, moment)


if __name__ == "__main__":
    sys.exit(main())
