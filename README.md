# Hermes Companion iOS - Always-On Location Transmitter for Hermes Agent

A dedicated iOS companion app built with one single mission: **reliably supply user location to your Hermes AI Agent at all times — even when the iPhone app is closed, suspended in the background, or restarted**.

---

## 🧭 The Solution: How Hermes Agent Fetches the Location

Because iOS restricts apps when closed, an external agent cannot directly inbound-HTTP-call an iPhone in your pocket (especially across cellular networks and NAT). 

Instead, Hermes Companion uses a **High-Availability Ingestion Relay + MCP Tool**:

```
[ iPhone (Closed / Pocket) ]
       │
       │ (Wakes on cell moves / geofence exits / periodic)
       │ Auto-POSTs coordinates via Wi-Fi / Cellular / Tailscale
       ▼
[ Hermes Location Relay (server/relay.py) ]
       ▲
       │ Instant Query (<2ms) via MCP or REST
       │
[ Hermes Agent (Autonomous AI) ]
   └── Calls tool: `get_user_location(max_age_minutes=60)`
```

1. **iOS App Transmits Silently**: Even when killed from the App Switcher, iOS wakes up the app whenever you move (~500m significant change) or exit your stationary geofence. The app POSTs the new coordinates, speed, battery, and timestamp to your Hermes Relay.
2. **Relay Stores State**: The lightweight Python relay (`server/relay.py`) stores the latest position in SQLite.
3. **Hermes Agent Fetches On-Demand**: Whenever Hermes needs to know where you are (e.g. for calendar events, weather, arrival estimates, local recommendations), Hermes executes `get_user_location()` through its native **Model Context Protocol (MCP)** tool or a simple `GET /api/location/latest` HTTP request.

---

## 🌟 How "Always Even When Closed" Works on iOS

iOS enforces strict sandboxing on background applications. If an app is swiped away by the user or terminated by iOS under memory pressure, normal background timers and standard continuous GPS loops stop. 

Hermes Companion implements a **Tri-Layer CoreLocation Engine** to guarantee execution:

### 1. Significant Location Change Service (`startMonitoringSignificantLocationChanges`)
- **Apple's Native Closed-State Wakeup**: This low-power API uses cell tower switching and Wi-Fi transitions (~500m movement).
- **Guaranteed Relaunch**: When movement occurs, iOS **automatically wakes or relaunches the terminated app in the background**.
- **`AppDelegate` Contract**: iOS launches the app with `UIApplication.LaunchOptionsKey.location`. `HermesCompanion` immediately initializes `LocationManager.shared` upon launch so the delegate receives and logs the event immediately.

### 2. Stationary Dynamic Perimeter Geofencing (`CLCircularRegion`)
- When you stay stationary for more than a minute, Hermes automatically sets a 100m circular geofence around your coordinates.
- If the app is closed, the moment you leave this perimeter, iOS triggers a **Region Exit Event**, which launches the app from its closed state, logs the departure, transitions back to active tracking, and transmits to Hermes.

### 3. Visits Monitoring Service (`startMonitoringVisits`)
- Uses Apple's machine-learned Visit Detection to log arrival and departure times at frequent points of interest. Wakes the app even when terminated.

### 4. Continuous Standard GPS (`allowsBackgroundLocationUpdates = true`)
- While traveling or while active in the background, standard high-precision GPS streams updates with distance filtering.

---

## 🗺️ Project File Map

```text
hermes-companion-ios/
├── AGENT.md                                # Context & operational instructions for AI agents
├── README.md                               # Project documentation & user guide
├── project.yml                             # XcodeGen specification defining targets & build settings
├── hermes-companion-ios.xcworkspace/       # Xcode workspace container
│   └── contents.xcworkspacedata            # Workspace mapping referencing HermesCompanion.xcodeproj
├── HermesCompanion.xcodeproj/              # Generated Xcode project (via `xcodegen generate`)
├── .gitignore                              # Git ignore rules for Xcode, DerivedData, and SQLite
├── HermesCompanion/                        # Main iOS Swift application sources
│   ├── App/
│   │   ├── AppDelegate.swift               # Handles iOS launchOptions[.location] and background tasks
│   │   └── HermesCompanionApp.swift        # SwiftUI App root with @UIApplicationDelegateAdaptor
│   ├── Models/
│   │   ├── AppDiagnosticEvent.swift        # Diagnostic log model (severity, timestamp, message)
│   │   ├── LocationRecord.swift            # Core location model (coords, accuracy, speed, battery, CloudKit CKRecord)
│   │   └── TrackingConfiguration.swift     # Profiles (Smart, Ultra, Battery), Pipeline (CloudKit, Webhook, Dual)
│   ├── Services/
│   │   ├── BackgroundTaskManager.swift     # BGTaskScheduler registration for refresh & processing
│   │   ├── CloudKitSyncManager.swift       # Apple CloudKit Private DB & Ubiquity container synchronizer
│   │   ├── LocationManager.swift           # CoreLocation manager (significant, geofence, visits, wakeups)
│   │   ├── LocationStore.swift             # Thread-safe persistent JSON store with GPX/GeoJSON/CSV export
│   │   └── SyncManager.swift               # HTTP transmission engine, batch uploader, test ping runner
│   ├── Views/
│   │   ├── MainTabView.swift               # 3-tab layout (Transmitter, Transmissions, Hermes Config)
│   │   ├── DashboardView.swift             # Primary transmitter telemetry UI and architecture guides
│   │   ├── HistoryLogView.swift            # Historical transmission stream and diagnostic event logs
│   │   ├── SettingsView.swift              # Pipeline selector (CloudKit / Webhook / Dual), CloudKit status & ping
│   │   └── Components/
│   │       ├── LocationRowView.swift       # Visual row for individual location fixes with trigger badges
│   │       ├── MetricTileView.swift        # Telemetry stat cards (Accuracy, Battery, Wakes, Sync count)
│   │       ├── PermissionBannerView.swift  # Dynamic alert guiding user to grant "Always Allow" in Settings
│   │       └── StatusCardView.swift        # Live GPS coordinate card, master toggle, and instant ping button
│   └── Resources/
│       ├── Info.plist                      # Privacy strings, background modes (location, fetch, processing, remote-notification)
│       ├── HermesCompanion.entitlements    # iCloud CloudKit & CloudDocuments container entitlements
│       └── Assets.xcassets/                # Xcode asset catalog (AppIcon and AccentColor)
│           ├── Contents.json
│           ├── AccentColor.colorset/Contents.json
│           └── AppIcon.appiconset/Contents.json
└── server/                                 # Hermes backend relay, MCP tools, and integration tests
    ├── bridge/
    │   └── HermesCloudKitBridge.swift      # Native macOS CloudKit CLI bridge (status, latest, history, daemon)
    ├── places.py                           # Semantic place & activity recognition engine (known places, geocoding)
    ├── places.json                         # Known places registry (Gym, Home, Work) with geofence radii
    ├── relay.py                            # Zero-dependency Python HTTP relay with SQLite persistence & places API
    ├── mcp_server.py                       # Model Context Protocol (MCP) server for Hermes Agent (stdio)
    ├── client.py                           # Python client module (iCloud, SQLite, & HTTP relay fallbacks + context)
    ├── skills/
    │   └── user-location/
    │       └── SKILL.md                    # Hermes agent skill for location awareness & conversational context
    ├── HERMES_AGENT_PROMPT.md              # System prompt and Heartbeat protocol specification for Hermes Agent
    └── test_integration.py                 # End-to-end integration test (ping, upload, REST fetch, MCP, iCloud)
```

---

## 🛠️ Hermes Agent Integration & Conversational Location Awareness

Hermes Agent understands not just raw GPS numbers, but **where Daniel is and what he is doing** (e.g. *"Hey Daniel, I see you are at the gym, how is it doing?"*).

### Option 1: Native MCP Server (Model Context Protocol)
Hermes registers the MCP server directly via:
```bash
love mcp add hermes-companion --command /usr/bin/python3 --args /Users/daniel/Workspace/hermes-companion-ios/server/mcp_server.py
```

Hermes Agent gains direct access to:
- `get_user_location(max_age_minutes=60)`: Returns place name, activity, context summary, suggested conversational opener, coordinates, accuracy, battery, and speed.
- `get_location_history(limit=20)`: Returns recent movement trajectory with resolved places.
- `add_known_place(name, category, latitude, longitude, radius_meters)`: Dynamically registers new places (e.g. gym, home, office).
- `list_known_places()`: Lists all configured places and geofences.

### Option 2: Python Helper (`server.client`)
Used directly in Python runtimes or heartbeat scripts:
```python
from server.client import get_user_location

loc = get_user_location()
# Enriched output with semantic context:
# loc["place_name"] -> "The Gym"
# loc["activity"]   -> "working out at the gym"
# loc["suggested_greeting"] -> "Hey Daniel, I see you are at the gym, how is it doing?"
```

### Option 3: Dedicated Hermes Skill (`user-location`)
Installed at `~/.hermes/profiles/love/skills/user-location/SKILL.md`. Automatically triggers when Daniel asks where he is, what he is doing, or during proactive heartbeats.

### Option 3: REST API (Relay Server)
Hermes Agent can query the local relay:
```bash
curl http://localhost:8080/api/location/latest
```
Response:
```json
{
  "status": "ok",
  "latitude": 52.520008,
  "longitude": 13.404954,
  "altitude_meters": 34.2,
  "accuracy_meters": 4.5,
  "speed_kmh": 0.0,
  "is_moving": false,
  "recorded_at": "2026-09-28T21:40:55Z",
  "age_seconds": 15,
  "age_human": "15s ago",
  "trigger_source": "Significant Change",
  "battery_percent": 88,
  "battery_state": "unplugged",
  "app_state": "resumed_terminated",
  "device_name": "Daniel's iPhone",
  "coordinates": "52.520008, 13.404954",
  "maps_link": "https://maps.apple.com/?ll=52.520008,13.404954&q=User+Location"
}
```

### Option 3: Python Script Import
```python
from server.client import get_user_location

location = get_user_location()
if location:
    print(f"Latitude: {location['latitude']}, Longitude: {location['longitude']}")
```

---

## 🚀 Running the System

### Step 1: Start the Relay Server on your Mac
```bash
python3 server/relay.py --port 8080
```
*(Tip: If accessing from outside home Wi-Fi, run over [Tailscale](https://tailscale.com) or Cloudflare Tunnel).*

### Step 2: Open and Run the iOS Companion App
1. Open `hermes-companion-ios.xcworkspace` in Xcode:
   ```bash
   open hermes-companion-ios.xcworkspace
   ```
2. Select your iPhone and press **Run (⌘R)**.
3. On first launch:
   - Select **"Allow While Using App"**, then tap the in-app banner to upgrade to **"Always Allow"** in iOS Settings (required by iOS to wake closed apps).
4. Go to **Hermes Config** tab in the app:
   - Set **Server URL** to your relay (e.g. `http://<your-mac-ip-or-tailscale>:8080/api/location`).
   - Tap **Send Test Ping** to verify connectivity.
   - Toggle **Auto-Sync Location Updates** to ON.

### Step 3: Run the Integration Test
Verify the whole loop (iOS ping, upload, latest fetch, and MCP stdio call):
```bash
python3 server/test_integration.py
```
