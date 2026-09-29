#!/usr/bin/env python3
"""
Hermes Location Relay Server
----------------------------
Lightweight, zero-dependency HTTP relay server with SQLite persistence.
Accepts location updates from Hermes Companion iOS and serves them
to Hermes Agent via REST API or MCP.

Usage:
    python3 server/relay.py [--port 8080] [--token SECRET_TOKEN]
"""

import sys
import os
import json
import sqlite3
import argparse
from datetime import datetime, timezone
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

DB_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "locations.sqlite3")
DEFAULT_PORT = 8080
AUTH_TOKEN = os.getenv("HERMES_LOCATION_TOKEN", "")

def init_db():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS locations (
            id TEXT PRIMARY KEY,
            device_id TEXT,
            device_name TEXT,
            recorded_at TEXT,
            received_at TEXT,
            latitude REAL,
            longitude REAL,
            altitude REAL,
            accuracy REAL,
            speed_mps REAL,
            course REAL,
            source TEXT,
            battery_level REAL,
            battery_state TEXT,
            app_state TEXT
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_recorded_at ON locations (recorded_at DESC)")
    conn.commit()
    conn.close()

def insert_location(record, device_id="unknown", device_name="iPhone"):
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    now_iso = datetime.now(timezone.utc).isoformat()
    cursor.execute("""
        INSERT OR REPLACE INTO locations (
            id, device_id, device_name, recorded_at, received_at,
            latitude, longitude, altitude, accuracy, speed_mps, course,
            source, battery_level, battery_state, app_state
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        record.get("id", str(os.urandom(8).hex())),
        device_id,
        device_name,
        record.get("timestamp", now_iso),
        now_iso,
        record.get("latitude", 0.0),
        record.get("longitude", 0.0),
        record.get("altitude", 0.0),
        record.get("horizontal_accuracy", 0.0),
        record.get("speed_mps", -1.0),
        record.get("course", -1.0),
        record.get("source", "Standard GPS"),
        record.get("battery_level", -1.0),
        record.get("battery_state", "unknown"),
        record.get("app_state", "active")
    ))
    conn.commit()
    conn.close()

def get_latest_location():
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM locations ORDER BY recorded_at DESC LIMIT 1")
    row = cursor.fetchone()
    conn.close()
    if not row:
        return None

    data = dict(row)
    # Calculate age in seconds
    try:
        dt = datetime.fromisoformat(data["recorded_at"].replace("Z", "+00:00"))
        age_seconds = int((datetime.now(timezone.utc) - dt).total_seconds())
    except Exception:
        age_seconds = 0

    speed_mps = data.get("speed_mps", -1.0)
    speed_kmh = max(0.0, speed_mps * 3.6) if speed_mps >= 0 else 0.0

    res = {
        "status": "ok",
        "latitude": data["latitude"],
        "longitude": data["longitude"],
        "altitude_meters": data["altitude"],
        "accuracy_meters": data["accuracy"],
        "speed_kmh": round(speed_kmh, 1),
        "is_moving": speed_kmh > 3.0,
        "recorded_at": data["recorded_at"],
        "age_seconds": max(0, age_seconds),
        "age_human": f"{age_seconds // 60}m {age_seconds % 60}s ago" if age_seconds >= 60 else f"{age_seconds}s ago",
        "trigger_source": data["source"],
        "battery_percent": int(data["battery_level"] * 100) if data["battery_level"] >= 0 else None,
        "battery_state": data["battery_state"],
        "app_state": data["app_state"],
        "device_name": data["device_name"],
        "coordinates": f"{data['latitude']:.6f}, {data['longitude']:.6f}",
        "maps_link": f"https://maps.apple.com/?ll={data['latitude']},{data['longitude']}&q=User+Location"
    }

    try:
        try:
            from server.places import get_places_manager
        except ImportError:
            from places import get_places_manager
        ctx = get_places_manager().resolve_context(
            data["latitude"],
            data["longitude"],
            speed_kmh=speed_kmh,
            is_moving=speed_kmh > 3.0,
            age_seconds=max(0, age_seconds),
        )
        res.update(ctx)
    except Exception:
        pass

    return res

def get_history(limit=50):
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM locations ORDER BY recorded_at DESC LIMIT ?", (limit,))
    rows = cursor.fetchall()
    conn.close()
    return [dict(r) for r in rows]

class HermesRequestHandler(BaseHTTPRequestHandler):
    def check_auth(self):
        if not AUTH_TOKEN:
            return True
        auth_header = self.headers.get("Authorization", "")
        if auth_header.startswith("Bearer "):
            token = auth_header[7:].strip()
            return token == AUTH_TOKEN
        return False

    def send_json(self, status_code, data):
        body = json.dumps(data, indent=2).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        query = parse_qs(parsed.query)

        if not self.check_auth():
            self.send_json(401, {"error": "Unauthorized: invalid or missing Bearer token"})
            return

        if path in ("", "/health"):
            latest = get_latest_location()
            self.send_json(200, {
                "service": "Hermes Location Relay",
                "status": "healthy",
                "has_location": latest is not None,
                "latest_age": latest["age_human"] if latest else None
            })
        elif path == "/api/location/latest":
            latest = get_latest_location()
            if latest:
                self.send_json(200, latest)
            else:
                self.send_json(404, {"error": "No locations recorded yet"})
        elif path == "/api/location/history":
            limit = int(query.get("limit", [50])[0])
            records = get_history(limit=min(limit, 500))
            self.send_json(200, {"count": len(records), "locations": records})
        elif path == "/api/places":
            try:
                try:
                    from server.places import get_places_manager
                except ImportError:
                    from places import get_places_manager
                places = [p.to_dict() for p in get_places_manager().list_places()]
                self.send_json(200, {"count": len(places), "places": places})
            except Exception as e:
                self.send_json(500, {"error": str(e)})
        else:
            self.send_json(404, {"error": f"Endpoint not found: {path}"})

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")

        if not self.check_auth():
            self.send_json(401, {"error": "Unauthorized: invalid or missing Bearer token"})
            return

        content_length = int(self.headers.get("Content-Length", 0))
        post_data = self.rfile.read(content_length)

        try:
            payload = json.loads(post_data.decode("utf-8")) if post_data else {}
        except Exception as e:
            self.send_json(400, {"error": f"Malformed JSON: {str(e)}"})
            return

        if path in ("/api/location", "/api/location/batch"):
            # Check for ping test
            if payload.get("type") == "ping":
                print(f"[{datetime.now().strftime('%H:%M:%S')}] Received test ping from {payload.get('device_name', 'iPhone')}")
                self.send_json(200, {"status": "pong", "message": "Hermes Relay reachable"})
                return

            device_id = payload.get("device_id", "unknown")
            device_name = payload.get("device_name", "iPhone")

            locations = payload.get("locations", [])
            # Also handle single record payload
            if not locations and "latitude" in payload:
                locations = [payload]

            for loc in locations:
                insert_location(loc, device_id=device_id, device_name=device_name)

            print(f"[{datetime.now().strftime('%H:%M:%S')}] Ingested {len(locations)} locations from {device_name}")
            self.send_json(200, {
                "status": "success",
                "ingested": len(locations),
                "timestamp": datetime.now(timezone.utc).isoformat()
            })
        elif path == "/api/places":
            try:
                try:
                    from server.places import get_places_manager
                except ImportError:
                    from places import get_places_manager
                p = get_places_manager().add_place(
                    name=payload["name"],
                    category=payload.get("category", "general"),
                    activity=payload.get("activity", f"at {payload['name']}"),
                    latitude=float(payload["latitude"]),
                    longitude=float(payload["longitude"]),
                    radius_meters=float(payload.get("radius_meters", 150.0)),
                    notes=payload.get("notes", ""),
                    place_id=payload.get("id"),
                )
                self.send_json(200, {"status": "created", "place": p.to_dict()})
            except Exception as e:
                self.send_json(400, {"error": f"Failed to add place: {str(e)}"})
        elif path == "/api/location/clear":
            conn = sqlite3.connect(DB_FILE)
            conn.execute("DELETE FROM locations")
            conn.commit()
            conn.close()
            self.send_json(200, {"status": "cleared"})
        else:
            self.send_json(404, {"error": f"Endpoint not found: {path}"})

    def log_message(self, format, *args):
        # Clean console log
        sys.stderr.write(f"[{self.log_date_time_string()}] {format % args}\n")

def run_server(port=DEFAULT_PORT, token=""):
    global AUTH_TOKEN
    if token:
        AUTH_TOKEN = token

    init_db()
    server_address = ("0.0.0.0", port)
    httpd = ThreadingHTTPServer(server_address, HermesRequestHandler)
    print(f"==================================================")
    print(f" Hermes Location Relay running on port {port}")
    print(f" Ingestion URL for iOS App: http://<this-host-ip>:{port}/api/location")
    print(f" Fetch URL for Hermes Agent: http://localhost:{port}/api/location/latest")
    if AUTH_TOKEN:
        print(f" Authentication: Bearer Token required")
    else:
        print(f" Authentication: None (Open on local network / Tailscale)")
    print(f" Database: {DB_FILE}")
    print(f"==================================================")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping relay server...")
        httpd.server_close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Hermes Location Relay Server")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Port to listen on (default: 8080)")
    parser.add_argument("--token", type=str, default="", help="Optional Bearer token for authentication")
    args = parser.parse_args()

    run_server(port=args.port, token=args.token)
