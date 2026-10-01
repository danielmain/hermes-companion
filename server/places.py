"""
Hermes Companion Places & Semantic Activity Recognition Engine
-------------------------------------------------------------
Identifies Daniel's physical context (e.g. at the gym, at home, at work, in transit)
using configured known places, radius geofencing, and cached reverse geocoding.
"""

from __future__ import annotations

import json
import math
import os
import sqlite3
import urllib.request
import urllib.error
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

DB_PATH = Path(__file__).resolve().parent / "locations.sqlite3"
LOVE_PROFILE_PLACES = Path.home() / ".hermes/profiles/love/state/places.json"
PLACES_JSON_PATH = LOVE_PROFILE_PLACES if LOVE_PROFILE_PLACES.parent.is_dir() else Path(__file__).resolve().parent / "places.json"

# GPS is write-on-accepted-move: latest_location.json is rewritten only when
# GPSPersistDecision accepts a displacement (default 30 m, or 150 m while stationary).
# The timestamp is therefore minutes-since-last-move, not "data went stale".
# Sitting still for hours is expected and means he is still at that place (a geofence
# would have fired if he left). This threshold only labels a long stay, never "lost".
STALE_FIX_SECONDS = 600

# CoreMotion activity (stationary/walking/running/driving) is refreshed independently of the
# GPS fix, so a reading younger than this tells what he is doing NOW.
MOTION_FRESH_SECONDS = 300


def haversine_distance_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate great-circle distance between two GPS points in meters."""
    R = 6371000.0  # Earth radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = (
        math.sin(delta_phi / 2.0) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2
    )
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    return R * c


@dataclass(frozen=True)
class KnownPlace:
    id: str
    name: str
    category: str  # gym, home, work, cafe, outdoors, general
    activity: str  # "working out at the gym", "resting at home", etc.
    latitude: float
    longitude: float
    radius_meters: float = 150.0
    notes: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# Default initial places
DEFAULT_PLACES: List[KnownPlace] = [
    KnownPlace(
        id="sample_gym",
        name="The Gym",
        category="gym",
        activity="working out at the gym",
        latitude=52.520008,
        longitude=13.404954,
        radius_meters=150.0,
        notes="Primary workout center / fitness studio",
    ),
    KnownPlace(
        id="home_base",
        name="Home",
        category="home",
        activity="at home",
        latitude=52.530000,
        longitude=13.410000,
        radius_meters=120.0,
        notes="Primary residence",
    ),
]


class PlacesManager:
    """Manages known places and resolves physical semantic context."""

    def __init__(self, db_path: Path = DB_PATH, places_file: Path = PLACES_JSON_PATH):
        self.db_path = db_path
        self.places_file = places_file
        self._init_db()
        self._ensure_default_places()

    def _get_connection(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self) -> None:
        """Create places tables if they do not exist."""
        with self._get_connection() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS known_places (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    category TEXT NOT NULL,
                    activity TEXT NOT NULL,
                    latitude REAL NOT NULL,
                    longitude REAL NOT NULL,
                    radius_meters REAL NOT NULL DEFAULT 150.0,
                    notes TEXT,
                    created_at TEXT NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS places_cache (
                    cache_key TEXT PRIMARY KEY,
                    latitude REAL NOT NULL,
                    longitude REAL NOT NULL,
                    display_name TEXT,
                    place_category TEXT,
                    address_json TEXT,
                    raw_json TEXT,
                    created_at TEXT NOT NULL
                )
                """
            )
            conn.commit()

    def _ensure_default_places(self) -> None:
        """Seed default places if table is empty."""
        # If places.json exists, always sync from it
        if self.places_file.is_file():
            try:
                data = json.loads(self.places_file.read_text(encoding="utf-8"))
                for item in data:
                    self.add_place(
                        name=item["name"],
                        category=item.get("category", "general"),
                        activity=item.get("activity", f"at {item['name']}"),
                        latitude=float(item["latitude"]),
                        longitude=float(item["longitude"]),
                        radius_meters=float(item.get("radius_meters", 150.0)),
                        notes=item.get("notes", ""),
                        place_id=item.get("id"),
                    )
                return
            except Exception:
                pass

        with self._get_connection() as conn:
            cur = conn.execute("SELECT COUNT(*) as cnt FROM known_places")
            cnt = cur.fetchone()["cnt"]
            if cnt == 0:

                # Otherwise insert default places
                now_str = datetime.now(timezone.utc).isoformat()
                for p in DEFAULT_PLACES:
                    conn.execute(
                        """
                        INSERT OR IGNORE INTO known_places
                        (id, name, category, activity, latitude, longitude, radius_meters, notes, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            p.id,
                            p.name,
                            p.category,
                            p.activity,
                            p.latitude,
                            p.longitude,
                            p.radius_meters,
                            p.notes,
                            now_str,
                        ),
                    )
                conn.commit()
                self._save_to_json_file()

    def _save_to_json_file(self) -> None:
        """Mirror known places to places.json for easy user inspection."""
        places = self.list_places()
        try:
            self.places_file.write_text(
                json.dumps([p.to_dict() for p in places], indent=2, ensure_ascii=False),
                encoding="utf-8",
            )
        except Exception:
            pass

    def add_place(
        self,
        name: str,
        category: str,
        activity: str,
        latitude: float,
        longitude: float,
        radius_meters: float = 150.0,
        notes: str = "",
        place_id: Optional[str] = None,
    ) -> KnownPlace:
        """Register or update a known place."""
        pid = place_id or name.lower().replace(" ", "_")
        now_str = datetime.now(timezone.utc).isoformat()
        with self._get_connection() as conn:
            conn.execute(
                """
                INSERT INTO known_places (id, name, category, activity, latitude, longitude, radius_meters, notes, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    category = excluded.category,
                    activity = excluded.activity,
                    latitude = excluded.latitude,
                    longitude = excluded.longitude,
                    radius_meters = excluded.radius_meters,
                    notes = excluded.notes
                """,
                (pid, name, category, activity, latitude, longitude, radius_meters, notes, now_str),
            )
            conn.commit()
        self._save_to_json_file()
        return KnownPlace(pid, name, category, activity, latitude, longitude, radius_meters, notes)

    def remove_place(self, place_id: str) -> bool:
        """Remove a known place by ID."""
        with self._get_connection() as conn:
            cur = conn.execute("DELETE FROM known_places WHERE id = ? OR name = ?", (place_id, place_id))
            conn.commit()
            deleted = cur.rowcount > 0
        if deleted:
            self._save_to_json_file()
        return deleted

    def list_places(self) -> List[KnownPlace]:
        """List all registered known places."""
        with self._get_connection() as conn:
            cur = conn.execute("SELECT * FROM known_places ORDER BY name ASC")
            rows = cur.fetchall()
            return [
                KnownPlace(
                    id=r["id"],
                    name=r["name"],
                    category=r["category"],
                    activity=r["activity"],
                    latitude=float(r["latitude"]),
                    longitude=float(r["longitude"]),
                    radius_meters=float(r["radius_meters"]),
                    notes=r["notes"] or "",
                )
                for r in rows
            ]

    def match_known_place(self, latitude: float, longitude: float) -> Optional[Dict[str, Any]]:
        """Check if coordinates fall inside any known place radius."""
        places = self.list_places()
        closest_match: Optional[KnownPlace] = None
        min_dist = float("inf")

        for place in places:
            dist = haversine_distance_meters(latitude, longitude, place.latitude, place.longitude)
            if dist <= place.radius_meters and dist < min_dist:
                min_dist = dist
                closest_match = place

        if closest_match:
            return {
                "matched": True,
                "place_id": closest_match.id,
                "place_name": closest_match.name,
                "place_category": closest_match.category,
                "activity": closest_match.activity,
                "distance_meters": round(min_dist, 1),
                "radius_meters": closest_match.radius_meters,
            }
        return None

    def reverse_geocode(self, latitude: float, longitude: float) -> Dict[str, Any]:
        """
        Reverse geocode coordinates using local SQLite cache with OSM Nominatim fallback.
        Cached by rounded coordinate (~30-50m grid) to minimize external network requests.
        """
        cache_key = f"{round(latitude, 4)}:{round(longitude, 4)}"
        with self._get_connection() as conn:
            cur = conn.execute("SELECT * FROM places_cache WHERE cache_key = ?", (cache_key,))
            row = cur.fetchone()
            if row:
                try:
                    addr = json.loads(row["address_json"]) if row["address_json"] else {}
                    return {
                        "display_name": row["display_name"],
                        "category": row["place_category"],
                        "address": addr,
                        "source": "cache",
                    }
                except Exception:
                    pass

        # Query Nominatim API with 3s timeout
        url = f"https://nominatim.openstreetmap.org/reverse?lat={latitude}&lon={longitude}&format=json&extratags=1&addressdetails=1"
        req = urllib.request.Request(url, headers={"User-Agent": "HermesCompanion/1.0 (Hermes Location Agent)"})
        try:
            with urllib.request.urlopen(req, timeout=3.5) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                display_name = data.get("display_name", "")
                addr = data.get("address", {})
                extratags = data.get("extratags", {})

                # Determine category & activity
                category = "general"
                amenity = data.get("amenity", "").lower()
                leisure = data.get("leisure", "").lower()
                name_low = display_name.lower()

                gym_keywords = ["gym", "fitness", "crossfit", "boulder", "workout", "kraftsport", "mcfit", "fitx", "john reed", "sports_centre"]
                if leisure == "fitness_centre" or amenity == "gym" or any(kw in name_low for kw in gym_keywords):
                    category = "gym"
                elif amenity in ["cafe", "coffee_shop", "restaurant", "bar", "pub"]:
                    category = "cafe"
                elif addr.get("building") in ["apartments", "residential", "house"] or "residential" in name_low:
                    category = "residential"
                elif amenity in ["coworking_space", "office"]:
                    category = "work"

                now_str = datetime.now(timezone.utc).isoformat()
                with self._get_connection() as conn:
                    conn.execute(
                        """
                        INSERT OR REPLACE INTO places_cache
                        (cache_key, latitude, longitude, display_name, place_category, address_json, raw_json, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            cache_key,
                            latitude,
                            longitude,
                            display_name,
                            category,
                            json.dumps(addr),
                            json.dumps(data),
                            now_str,
                        ),
                    )
                    conn.commit()

                return {
                    "display_name": display_name,
                    "category": category,
                    "address": addr,
                    "source": "nominatim",
                }
        except Exception as e:
            return {
                "display_name": f"{latitude:.5f}, {longitude:.5f}",
                "category": "unknown",
                "address": {},
                "source": "fallback",
                "error": str(e),
            }

    def resolve_context(
        self,
        latitude: float,
        longitude: float,
        speed_kmh: float = 0.0,
        is_moving: bool = False,
        age_seconds: int = 0,
        motion_activity: str = "unknown",
        motion_age_seconds: int = 999999,
    ) -> Dict[str, Any]:
        """
        Synthesize semantic context: place, activity, movement, and a greeting.

        Two independent signals:
          - GPS (age_seconds): WHERE he is. The file is rewritten only when a move is
            accepted (default 30 m, or 150 m while stationary). Age is minutes since last move. He is still
            at that place until GPS writes again (a geofence would fire if he left).
          - CoreMotion (motion_age_seconds): whether he is moving NOW (walking/running/
            driving/stationary), refreshed independently of GPS.

        Rules:
          - GPS place is current until a new coordinate is written.
          - Fresh motion is authoritative for moving vs staying *right now*.
          - A long GPS age while at a place means he has been there that long.
        """
        long_stay = age_seconds > STALE_FIX_SECONDS
        minutes_since_last_move = int(age_seconds // 60) if age_seconds else 0

        valid_motion = motion_activity in ("stationary", "walking", "running", "cycling", "automotive")
        motion_fresh = valid_motion and motion_age_seconds <= MOTION_FRESH_SECONDS
        motion_moving = motion_activity in ("walking", "running", "cycling", "automotive")
        motion_label = {
            "walking": "walking",
            "running": "running",
            "cycling": "cycling",
            "automotive": "driving",
        }.get(motion_activity)

        fix_moving = is_moving or speed_kmh > 3.0
        # Without fresh motion, GPS speed is only meaningful on a *recent* write
        # (he just moved). An old write with leftover speed is not "moving now".
        is_moving_now = motion_moving if motion_fresh else (fix_moving and not long_stay)

        base = {
            "is_stale": long_stay,
            "fix_age_minutes": minutes_since_last_move,
            "minutes_since_last_move": minutes_since_last_move,
            "motion_activity": motion_activity if valid_motion else "unknown",
            "motion_age_seconds": motion_age_seconds,
            "motion_fresh": motion_fresh,
            "is_moving_now": is_moving_now,
        }

        known = self.match_known_place(latitude, longitude)

        stay_txt = ""
        if minutes_since_last_move >= 1:
            stay_txt = f" (hasn't moved in ~{minutes_since_last_move} min)"

        # 1) Moving now. GPS still answers WHERE (last written coordinate).
        if is_moving_now:
            if known and motion_label in ("walking", "running", "cycling"):
                p_name = known["place_name"]
                act = f"{motion_label} at {p_name}"
                summary = f"At {p_name}, {motion_label} now{stay_txt}"
                return {
                    **base,
                    "place_name": p_name,
                    "place_category": known["place_category"],
                    "activity": act,
                    "context_summary": summary,
                    "suggested_greeting": f"Hey Daniel, I see you're at {p_name} — looks like you're {motion_label}. How is it going?",
                    "is_at_known_place": True,
                    "known_place_id": known["place_id"],
                    "distance_to_center_meters": known["distance_meters"],
                    "was_moving_at_fix": True,
                }

            if motion_fresh and motion_label:
                act = motion_label
                summary = f"Moving now ({act}); last GPS write {minutes_since_last_move} min ago"
            elif speed_kmh > 35.0:
                act = "driving or transit"
                summary = f"In transit (driving) at {speed_kmh:.1f} km/h"
            elif speed_kmh > 12.0:
                act = "cycling or fast transit"
                summary = f"In transit (cycling) at {speed_kmh:.1f} km/h"
            else:
                act = "walking or running"
                summary = f"In transit (walking/running) at {speed_kmh:.1f} km/h"
            return {
                **base,
                "place_name": "In Transit",
                "place_category": "transit",
                "activity": act,
                "context_summary": summary,
                "suggested_greeting": "Hey Daniel, looks like you're on the move! Where are you headed?",
                "is_at_known_place": False,
                "duration_stationary": None,
                "was_moving_at_fix": True,
            }

        stationary_now = motion_fresh and not motion_moving

        if known:
            p_name = known["place_name"]
            p_cat = known["place_category"]
            act = known["activity"]

            if p_cat == "gym":
                greeting = "Hey Daniel, I see you are at the gym, how is it doing?"
            elif p_cat == "home":
                # Sin lenguaje de llegada: la coordenada es write-on-change y la deriva
                # del GPS la reescribe estando él quieto en casa (medido 30/9: escrituras
                # 09:22 y 10:34 con él en casa toda la mañana). Un timestamp fresco no es
                # prueba de que acaba de volver, así que el texto dice dónde está, nunca
                # cuándo llegó.
                greeting = "Hey Daniel, you are at home. How are you feeling?"
            elif p_cat == "work":
                greeting = f"Hey Daniel, I see you're at work at {p_name}. How is the day going?"
            elif p_cat == "cafe":
                greeting = f"Hey Daniel, enjoying some time at {p_name}?"
            else:
                greeting = f"Hey Daniel, I see you're at {p_name}, how is it going?"

            if stationary_now and minutes_since_last_move >= 1:
                summary = f"At {p_name} (still there; hasn't moved in ~{minutes_since_last_move} min)"
            elif stationary_now:
                summary = f"At {p_name} (still there)"
            else:
                summary = f"At {p_name}{stay_txt}"

            return {
                **base,
                "place_name": p_name,
                "place_category": p_cat,
                "activity": act,
                "context_summary": summary,
                "suggested_greeting": greeting,
                "is_at_known_place": True,
                "known_place_id": known["place_id"],
                "distance_to_center_meters": known["distance_meters"],
                "was_moving_at_fix": False,
            }

        # Reverse geocoding fallback. Same write-on-change rule: he is still there.
        rev = self.reverse_geocode(latitude, longitude)
        cat = rev.get("category", "general")
        disp = rev.get("display_name", "")
        addr = rev.get("address", {})

        short_name = (
            addr.get("amenity")
            or addr.get("road")
            or addr.get("suburb")
            or addr.get("city")
            or f"{latitude:.4f}, {longitude:.4f}"
        )

        if cat == "gym":
            act = f"working out at {short_name}"
            greeting = "Hey Daniel, I see you are at the gym, how is it doing?"
        elif cat == "cafe":
            act = f"at {short_name}"
            greeting = f"Hey Daniel, I see you're at a cafe ({short_name}), how is it going?"
        elif cat == "residential":
            act = "at a residence"
            greeting = "Hey Daniel, looks like you're indoors. How are things going?"
        else:
            act = f"around {short_name}"
            greeting = f"Hey Daniel, I see you're around {short_name}, how is it going?"

        if stationary_now and minutes_since_last_move >= 1:
            summary = f"Around {short_name} (still there; hasn't moved in ~{minutes_since_last_move} min)"
        elif stationary_now:
            summary = f"Around {short_name} (still there)"
        else:
            summary = f"Around {short_name} ({cat}){stay_txt}"

        return {
            **base,
            "place_name": short_name,
            "place_category": cat,
            "activity": act,
            "context_summary": summary,
            "suggested_greeting": greeting,
            "is_at_known_place": False,
            "full_address": disp,
            "address_parts": addr,
            "was_moving_at_fix": False,
        }


# Singleton accessor
_manager: Optional[PlacesManager] = None

def get_places_manager() -> PlacesManager:
    global _manager
    if _manager is None:
        _manager = PlacesManager()
    return _manager
