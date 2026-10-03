"""
Hermes Companion Places & Semantic Activity Recognition Engine
-------------------------------------------------------------
Identifies the user's physical context (for example at the gym, at home, at work, in transit)
using configured known places, radius geofencing, and cached reverse geocoding.
"""

from __future__ import annotations

import json
import math
import os
import sqlite3
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
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

DB_PATH: Final[Path] = Path(__file__).resolve().parent / "locations.sqlite3"


# ==============================================================================
# Typed Structures (no Any)
# ==============================================================================

class PlaceDict(TypedDict, total=False):
    id: str
    name: str
    category: str
    activity: str
    latitude: float
    longitude: float
    radius_meters: float
    notes: str


class MatchedPlaceDict(TypedDict, total=False):
    matched: bool
    place_id: str
    place_name: str
    place_category: str
    activity: str
    distance_meters: float
    radius_meters: float


class ReverseGeocodeResult(TypedDict, total=False):
    display_name: str
    category: str
    address: Mapping[str, object]
    source: str
    error: str


class PlaceContextDict(TypedDict, total=False):
    is_stale: bool
    fix_age_minutes: int
    minutes_since_last_move: int
    motion_activity: str
    motion_age_seconds: int
    motion_fresh: bool
    is_moving_now: bool
    place_name: str
    place_category: str
    activity: str
    context_summary: str
    suggested_greeting: str
    is_at_known_place: bool
    known_place_id: Optional[str]
    distance_to_center_meters: Optional[float]
    was_moving_at_fix: bool
    duration_stationary: Optional[int]
    full_address: str
    address_parts: Mapping[str, object]


def default_places_path() -> Path:
    """Places file for this machine, with no profile name baked in.

    Order: HERMES_COMPANION_PLACES, HERMES_HOME/state/places.json, the only
    Hermes profile that already has state/places.json, then a shared file
    under ~/.hermes/hermes-companion/, then server/places.json.
    """
    env = os.environ.get("HERMES_COMPANION_PLACES", "").strip()
    if env:
        return Path(env).expanduser()
    hermes_home = os.environ.get("HERMES_HOME", "").strip()
    if hermes_home:
        # Strictly stay within HERMES_HOME without falling through if state/ is fresh
        return Path(hermes_home).expanduser() / "state" / "places.json"
    profiles = Path.home() / ".hermes" / "profiles"
    found = sorted(profiles.glob("*/state/places.json")) if profiles.is_dir() else []
    if len(found) == 1:
        return found[0]
    shared = Path.home() / ".hermes" / "hermes-companion" / "places.json"
    if shared.is_file():
        return shared
    return Path(__file__).resolve().parent / "places.json"


PLACES_JSON_PATH: Final[Path] = default_places_path()

# GPS is write-on-accepted-move: latest_location.json is rewritten only when
# GPSPersistDecision accepts a displacement (default 30 m, or 150 m while stationary).
# The timestamp is therefore minutes-since-last-move, not "data went stale".
STALE_FIX_SECONDS: Final[int] = 600

# CoreMotion activity (stationary/walking/running/driving) is refreshed independently of the
# GPS fix, so a reading younger than this tells what the user is doing now.
MOTION_FRESH_SECONDS: Final[int] = 300


def haversine_distance_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate great-circle distance between two GPS points in meters."""
    radius = 6_371_000.0  # Earth radius in meters
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = (
        math.sin(delta_phi / 2.0) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2
    )
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    return radius * c


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

    def to_dict(self) -> PlaceDict:
        return {
            "id": self.id,
            "name": self.name,
            "category": self.category,
            "activity": self.activity,
            "latitude": self.latitude,
            "longitude": self.longitude,
            "radius_meters": self.radius_meters,
            "notes": self.notes,
        }


# Default initial places
DEFAULT_PLACES: Final[Tuple[KnownPlace, ...]] = (
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
)


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
            self.places_file.parent.mkdir(parents=True, exist_ok=True)
            self.places_file.write_text(
                json.dumps([p.to_dict() for p in places], indent=2, ensure_ascii=False) + "\n",
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

    def match_known_place(self, latitude: float, longitude: float) -> Optional[MatchedPlaceDict]:
        """Check if coordinates fall inside any known place radius using functional selection."""
        places = self.list_places()
        matches = [
            (dist, place)
            for place in places
            for dist in [haversine_distance_meters(latitude, longitude, place.latitude, place.longitude)]
            if dist <= place.radius_meters
        ]

        if not matches:
            return None

        best_dist, best_place = min(matches, key=lambda item: item[0])
        return {
            "matched": True,
            "place_id": best_place.id,
            "place_name": best_place.name,
            "place_category": best_place.category,
            "activity": best_place.activity,
            "distance_meters": round(best_dist, 1),
            "radius_meters": best_place.radius_meters,
        }

    def reverse_geocode(self, latitude: float, longitude: float) -> ReverseGeocodeResult:
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
                    addr: Mapping[str, object] = json.loads(row["address_json"]) if row["address_json"] else {}
                    return {
                        "display_name": row["display_name"],
                        "category": row["place_category"],
                        "address": addr,
                        "source": "cache",
                    }
                except Exception:
                    pass

        url = f"https://nominatim.openstreetmap.org/reverse?lat={latitude}&lon={longitude}&format=json&extratags=1&addressdetails=1"
        req = urllib.request.Request(url, headers={"User-Agent": "HermesCompanion/1.0 (Hermes Location Agent)"})
        try:
            with urllib.request.urlopen(req, timeout=3.5) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                display_name = str(data.get("display_name", ""))
                addr = data.get("address", {}) if isinstance(data.get("address"), dict) else {}

                category = "general"
                amenity = str(data.get("amenity", "")).lower()
                leisure = str(data.get("leisure", "")).lower()
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
        is_moving: bool = False,
        age_seconds: int = 0,
        motion_activity: str = "unknown",
        motion_age_seconds: int = 999999,
    ) -> PlaceContextDict:
        """
        Synthesize semantic context: place, activity, movement, and greeting.
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

        fix_moving = is_moving
        is_moving_now = motion_moving if motion_fresh else (fix_moving and not long_stay)

        base: PlaceContextDict = {
            "is_stale": long_stay,
            "fix_age_minutes": minutes_since_last_move,
            "minutes_since_last_move": minutes_since_last_move,
            "motion_activity": motion_activity if valid_motion else "unknown",
            "motion_age_seconds": motion_age_seconds,
            "motion_fresh": motion_fresh,
            "is_moving_now": is_moving_now,
        }

        known = self.match_known_place(latitude, longitude)
        stay_txt = f" (hasn't moved in ~{minutes_since_last_move} min)" if minutes_since_last_move >= 1 else ""

        if is_moving_now:
            if known and motion_label in ("walking", "running", "cycling"):
                p_name = known["place_name"]
                act = motion_label
                summary = f"At {p_name}, {motion_label} now{stay_txt}"
                return {
                    **base,
                    "place_name": p_name,
                    "place_category": known["place_category"],
                    "activity": act,
                    "context_summary": summary,
                    "suggested_greeting": f"At {p_name}, {motion_label}.",
                    "is_at_known_place": True,
                    "known_place_id": known["place_id"],
                    "distance_to_center_meters": known["distance_meters"],
                    "was_moving_at_fix": True,
                }

            act = motion_label if (motion_fresh and motion_label) else "in transit"
            summary = f"Moving now ({act}); last GPS write {minutes_since_last_move} min ago" if (motion_fresh and motion_label) else f"In transit; last GPS write {minutes_since_last_move} min ago"
            return {
                **base,
                "place_name": "In Transit",
                "place_category": "transit",
                "activity": act,
                "context_summary": summary,
                "suggested_greeting": "On the move.",
                "is_at_known_place": False,
                "duration_stationary": None,
                "was_moving_at_fix": True,
            }

        stationary_now = motion_fresh and not motion_moving

        if known:
            p_name = known["place_name"]
            p_cat = known["place_category"]
            act = known["activity"]

            greetings = {
                "gym": "At the gym.",
                "home": "At home.",
                "work": f"At work at {p_name}.",
                "cafe": f"At {p_name}.",
            }
            greeting = greetings.get(p_cat, f"At {p_name}.")

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

        rev = self.reverse_geocode(latitude, longitude)
        cat = rev.get("category", "general")
        disp = rev.get("display_name", "")
        addr = rev.get("address", {})

        short_name = (
            str(addr.get("amenity"))
            if addr.get("amenity")
            else (
                str(addr.get("road"))
                if addr.get("road")
                else (
                    str(addr.get("suburb"))
                    if addr.get("suburb")
                    else (str(addr.get("city")) if addr.get("city") else f"{latitude:.4f}, {longitude:.4f}")
                )
            )
        )

        greetings_map = {
            "gym": ("working out at {name}", "At the gym."),
            "cafe": ("at {name}", f"At a cafe ({short_name})."),
            "residential": ("at a residence", "Indoors."),
        }
        act_tmpl, greeting = greetings_map.get(cat, (f"around {short_name}", f"Around {short_name}."))
        act = act_tmpl.format(name=short_name)

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
