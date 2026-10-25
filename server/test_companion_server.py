"""
Unit and integration tests for Hermes Companion Direct Connection HTTP Daemon.
"""

from __future__ import annotations

import json
import os
import shutil
import tempfile
import threading
import time
import unittest
from http.client import HTTPConnection
from pathlib import Path

import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from server.companion_server import (
    CompanionRequestHandler,
    ThreadingHTTPServer,
    SERVER_VERSION,
)


class TestCompanionServer(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.test_dir = Path(tempfile.mkdtemp(prefix="hermes_server_test_"))
        cls.token = "test_bearer_token_12345"
        cls.port = 18787

        cls.server = ThreadingHTTPServer(("127.0.0.1", cls.port), CompanionRequestHandler)
        cls.server.auth_token = cls.token  # type: ignore[attr-defined]
        cls.server.storage_dir = cls.test_dir  # type: ignore[attr-defined]

        cls.server_thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.server_thread.start()
        time.sleep(0.1)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        shutil.rmtree(cls.test_dir, ignore_errors=True)

    def request(
        self,
        method: str,
        path: str,
        body: Optional[dict] = None,
        token: Optional[str] = None,
    ) -> tuple[int, dict]:
        conn = HTTPConnection("127.0.0.1", self.port)
        headers = {}
        auth = token if token is not None else self.token
        if auth:
            headers["Authorization"] = f"Bearer {auth}"
        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        conn.request(method, path, body=data, headers=headers)
        res = conn.getresponse()
        resp_data = res.read().decode("utf-8")
        conn.close()
        parsed = {}
        if resp_data:
            try:
                parsed = json.loads(resp_data)
            except Exception:
                parsed = {"raw": resp_data}
        return res.status, parsed

    def test_01_health_unauthorized(self) -> None:
        status, data = self.request("GET", "/api/v1/health", token="wrong_token")
        self.assertEqual(status, 401)
        self.assertEqual(data.get("error"), "Unauthorized")

    def test_02_health_authorized(self) -> None:
        status, data = self.request("GET", "/api/v1/health")
        self.assertEqual(status, 200)
        self.assertEqual(data.get("status"), "ok")
        self.assertEqual(data.get("version"), SERVER_VERSION)

    def test_03_put_telemetry_latest_location(self) -> None:
        payload = {
            "latitude": 52.5200,
            "longitude": 13.4050,
            "recorded_at": "2026-10-21T08:00:00Z",
            "accuracy_meters": 5.0,
            "movement_reason": "moved",
        }
        status, data = self.request("PUT", "/api/v1/telemetry/latest_location.json", body=payload)
        self.assertEqual(status, 200)
        self.assertEqual(data.get("status"), "ok")

        target_file = self.test_dir / "latest_location.json"
        self.assertTrue(target_file.is_file())
        saved = json.loads(target_file.read_text(encoding="utf-8"))
        self.assertEqual(saved.get("latitude"), 52.5200)

    def test_04_put_telemetry_invalid_payload(self) -> None:
        # Missing latitude/longitude
        bad_payload = {"invalid_key": "bad_data"}
        status, data = self.request("PUT", "/api/v1/telemetry/latest_location.json", body=bad_payload)
        self.assertEqual(status, 422)

    def test_05_put_telemetry_location_history(self) -> None:
        payload = {
            "updated_at": "2026-10-21T08:00:00Z",
            "count": 1,
            "records": [
                {
                    "latitude": 52.5200,
                    "longitude": 13.4050,
                    "timestamp": "2026-10-21T08:00:00Z",
                }
            ]
        }
        status, data = self.request("PUT", "/api/v1/telemetry/location_history.json", body=payload)
        self.assertEqual(status, 200)
        target_file = self.test_dir / "location_history.json"
        self.assertTrue(target_file.is_file())

    def test_06_put_telemetry_latest_health(self) -> None:
        payload = {
            "timestamp": "2026-10-21T08:00:00Z",
            "vitals": {
                "stepCountToday": 8500,
                "recoveryStatus": "rested",
            }
        }
        status, data = self.request("PUT", "/api/v1/telemetry/latest_health.json", body=payload)
        self.assertEqual(status, 200)
        target_file = self.test_dir / "latest_health.json"
        self.assertTrue(target_file.is_file())

    def test_07_places_sync(self) -> None:
        places_payload = [
            {
                "id": "place_home",
                "name": "Home",
                "category": "home",
                "latitude": 52.5200,
                "longitude": 13.4050,
                "radius_meters": 100.0,
            }
        ]
        status, data = self.request("PUT", "/api/v1/places", body=places_payload)
        self.assertEqual(status, 200)
        self.assertEqual(data.get("count"), 1)

        # GET places
        status, get_data = self.request("GET", "/api/v1/places")
        self.assertEqual(status, 200)
        self.assertIsInstance(get_data, list)
        self.assertEqual(len(get_data), 1)
        self.assertEqual(get_data[0].get("name"), "Home")

    def test_08_inbox_post_and_get_pending(self) -> None:
        # 1. Post a new user letter
        msg_payload = {
            "subject": "Status Report",
            "body": "Hello from iPhone via Direct HTTP connection!",
            "target_profile": "default",
        }
        status, data = self.request("POST", "/api/v1/inbox/messages", body=msg_payload)
        self.assertEqual(status, 200)
        thread_id = data.get("thread_id")
        self.assertTrue(thread_id and thread_id.startswith("th_"))

        # Verify on disk
        thread_folder = self.test_dir / "threads" / thread_id
        self.assertTrue(thread_folder.is_dir())
        meta_file = thread_folder / "meta.json"
        self.assertTrue(meta_file.is_file())
        meta = json.loads(meta_file.read_text(encoding="utf-8"))
        self.assertEqual(meta.get("status"), "pending_agent")
        self.assertEqual(meta.get("subject"), "Status Report")

        # 2. Get pending inbox
        status, inbox_data = self.request("GET", "/api/v1/inbox/pending")
        self.assertEqual(status, 200)
        threads = inbox_data.get("threads", [])
        self.assertEqual(len(threads), 1)
        self.assertEqual(threads[0].get("id"), thread_id)
        self.assertEqual(len(threads[0].get("messages", [])), 1)
        self.assertEqual(threads[0]["messages"][0].get("body"), "Hello from iPhone via Direct HTTP connection!")


if __name__ == "__main__":
    unittest.main()
