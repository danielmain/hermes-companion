#!/usr/bin/env python3
"""
Integration test for Hermes Location Relay and MCP Server
"""

import subprocess
import time
import urllib.request
import json
import os
import sys

def run_test():
    print("1. Starting relay server on port 8089...")
    server_proc = subprocess.Popen(
        [sys.executable, "server/relay.py", "--port", "8089"],
        cwd="/Users/daniel/Workspace/hermes-companion-ios",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    time.sleep(1)

    try:
        print("2. Simulating iOS app sending test ping...")
        ping_payload = {
            "type": "ping",
            "device_name": "Daniel's iPhone",
            "timestamp": "2026-09-28T21:40:00Z"
        }
        req = urllib.request.Request(
            "http://127.0.0.1:8089/api/location",
            data=json.dumps(ping_payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            print(f"   Ping response: {data}")
            assert data.get("status") == "pong"

        print("3. Simulating iOS app waking from closed state and transmitting location...")
        location_payload = {
            "device_id": "TEST-DEVICE-UUID-1234",
            "device_name": "Daniel's iPhone",
            "sent_at": "2026-09-28T21:41:00Z",
            "locations": [
                {
                    "id": "fix-001",
                    "timestamp": "2026-09-28T21:40:55Z",
                    "latitude": 52.520008,
                    "longitude": 13.404954,
                    "altitude": 34.2,
                    "horizontal_accuracy": 4.5,
                    "speed_mps": 0.0,
                    "course": 0.0,
                    "source": "Launch (Woke App)",
                    "battery_level": 0.88,
                    "battery_state": "unplugged",
                    "app_state": "resumed_terminated"
                }
            ]
        }
        req2 = urllib.request.Request(
            "http://127.0.0.1:8089/api/location",
            data=json.dumps(location_payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req2) as resp:
            data = json.loads(resp.read().decode())
            print(f"   Upload response: {data}")
            assert data.get("ingested") == 1

        print("4. Fetching latest location via REST API (what Hermes Agent calls)...")
        with urllib.request.urlopen("http://127.0.0.1:8089/api/location/latest") as resp:
            latest = json.loads(resp.read().decode())
            print(f"   Latest location fetched:")
            print(f"   • Coordinates: {latest['coordinates']}")
            print(f"   • Accuracy: {latest['accuracy_meters']}m")
            print(f"   • Trigger Source: {latest['trigger_source']}")
            print(f"   • App State: {latest['app_state']}")
            print(f"   • Battery: {latest['battery_percent']}%")
            assert latest["latitude"] == 52.520008

        print("5. Testing MCP Server JSON-RPC stdio call...")
        mcp_env = os.environ.copy()
        mcp_env["HERMES_RELAY_URL"] = "http://127.0.0.1:8089"
        mcp_proc = subprocess.Popen(
            [sys.executable, "server/mcp_server.py"],
            cwd="/Users/daniel/Workspace/hermes-companion-ios",
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=mcp_env
        )

        init_msg = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}) + "\n"
        mcp_proc.stdin.write(init_msg.encode("utf-8"))
        mcp_proc.stdin.flush()
        init_resp = json.loads(mcp_proc.stdout.readline().decode("utf-8"))
        print(f"   MCP initialize: {init_resp['result']['serverInfo']}")

        tool_msg = json.dumps({
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": {"name": "get_user_location", "arguments": {}}
        }) + "\n"
        mcp_proc.stdin.write(tool_msg.encode("utf-8"))
        mcp_proc.stdin.flush()
        tool_resp = json.loads(mcp_proc.stdout.readline().decode("utf-8"))
        print(f"   MCP tool call result:\n{tool_resp['result']['content'][0]['text']}")

        mcp_proc.terminate()

        print("6. Testing client.py iCloud container parsing and zero-network reading...")
        from client import format_location_payload, get_user_location
        test_icloud_json = {
            "id": "ck-test-fix-777",
            "timestamp": "2026-09-28T21:40:55Z",
            "latitude": 48.858844,
            "longitude": 2.294351,
            "altitude": 35.0,
            "horizontal_accuracy": 3.2,
            "speed_mps": 1.2,
            "course": 90.0,
            "source": "CloudKit Private DB",
            "battery_level": 0.95,
            "battery_state": "charging",
            "app_state": "background",
            "device_name": "Daniel's iPhone 16"
        }
        temp_icloud_file = "/tmp/hermes_latest_location.json"
        with open(temp_icloud_file, "w", encoding="utf-8") as f:
            json.dump(test_icloud_json, f)

        parsed_loc = get_user_location(prefer_icloud=True)
        assert parsed_loc is not None
        assert parsed_loc["latitude"] == 48.858844
        assert parsed_loc["accuracy_meters"] == 3.2
        assert parsed_loc["battery_percent"] == 95
        assert "maps_link" in parsed_loc
        print(f"   Successfully read from iCloud local sync cache:")
        print(f"   • Coordinates: {parsed_loc['coordinates']}")
        print(f"   • Accuracy: ±{parsed_loc['accuracy_meters']}m")
        print(f"   • Source Channel: {parsed_loc['source_channel']}")

        # Clean up temp file
        if os.path.exists(temp_icloud_file):
            os.remove(temp_icloud_file)

        print("\nAll integration tests passed successfully!")
    finally:
        server_proc.terminate()
        server_proc.wait()

if __name__ == "__main__":
    run_test()
