# Hermes Companion iOS - Always-On Location & Apple Health Transmitter for Hermes Agent

A dedicated iOS companion app built with a dual mission:
1. **Always-On Physical Location:** Reliably supply user location and movement context to your Hermes AI Agent at all times — even when the iPhone app is closed, suspended in the background, or restarted.
2. **Apple Health & Wellness Telemetry:** Seamlessly stream deduplicated sleep analysis, active/recent workouts, resting heart rate, HRV, and daily recovery status so Hermes (Rukara) can converse naturally about your sleep quality, congratulate workouts, and proactively remind you to refuel with 30-40g protein and water.

---

## 🧭 The Solution: Zero-TCP Sync via Apple iCloud

Because iOS restricts apps when closed, and both the iPhone and the Mac can sit behind NAT / carrier CGNAT, there is **no inbound connection and no relay server**.
The only transport is **iCloud Drive / CloudKit sync** — Apple's own end-to-end encrypted channel between the two devices under the same Apple ID.

```
[ iPhone (Closed / Pocket) ]
       │
       │ (Wakes on cell moves / geofence exits / HealthKit background observers)
       │ Writes JSON into the app's iCloud/CloudKit ubiquity container
       ▼
[ iCloud Drive — Apple sync (bird daemon) ]
       │
       │ macOS materialises the files locally (zero network on the Mac)
       ▼
[ ~/Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/Documents/ ]
       ├── latest_location.json
       └── latest_health.json
       ▲
       │ Read locally via MCP tools / Python helper
       │
[ Hermes Agent (Autonomous AI) ]
       ├── Calls: `get_user_location()`
       ├── Calls: `get_user_health()`
       └── Calls: `get_user_physical_context()`
```

1. **iOS App Writes Silently**: Even when killed from the App Switcher, iOS wakes the app whenever you move (~500m significant change), exit your stationary geofence, or record Apple Health events (sleep/workouts). The app writes coordinates and health telemetry into its iCloud ubiquity container.
2. **GPS is write-on-change**: A new location record is stored, and `latest_location.json` is rewritten, **only when the GPS coordinate actually moves** (default 10 m, the Standard Distance Filter). Stationary GPS ticks do not append history, do not update file mtime, and do not trigger iCloud re-sync. The timestamp in `latest_location.json` is the last time the position changed; CoreMotion `motion_activity` answers whether you are moving right now.
3. **iCloud Syncs Automatically**: Apple mirrors those files down to the Mac's local iCloud container — no open ports, no background server, no NAT traversal.
4. **Hermes Agent Reads On-Demand**: Whenever Hermes needs your location or health context (e.g. for morning greetings, workout check-ins, or post-workout protein reminders), it reads the local synced files via native **Model Context Protocol (MCP)** tools or the Python helper.

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
│   │   └── TrackingConfiguration.swift     # Profiles (Smart, Ultra, Battery) and CloudKit sync parameters
│   ├── Services/
│   │   ├── BackgroundTaskManager.swift     # BGTaskScheduler registration for refresh & processing
│   │   ├── CloudKitSyncManager.swift       # Apple CloudKit Private DB & Ubiquity container synchronizer
│   │   ├── LocationManager.swift           # CoreLocation manager (significant, geofence, visits, wakeups)
│   │   └── LocationStore.swift             # Thread-safe persistent JSON store with GPX/GeoJSON/CSV export
│   ├── Views/
│   │   ├── MainTabView.swift               # 3-tab layout (Transmitter, Transmissions, Hermes Config)
│   │   ├── DashboardView.swift             # Primary transmitter telemetry UI and architecture guides
│   │   ├── HistoryLogView.swift            # Historical transmission stream and diagnostic event logs
│   │   ├── SettingsView.swift              # Pipeline selector (CloudKit), CloudKit status & ping
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
└── server/                                 # Hermes macOS integration: MCP tools & tests
    ├── places.py                           # Semantic place & activity recognition engine (known places, geocoding)
    ├── places.json                         # Known places registry (Gym, Home, Work) with geofence radii
    ├── mcp_server.py                       # Model Context Protocol (MCP) server for Hermes Agent (stdio)
    ├── client.py                           # Python client module (reads synced iCloud file + local SQLite cache)
    ├── skills/
    │   └── user-location/
    │       └── SKILL.md                    # Hermes agent skill for location awareness & conversational context
    ├── HERMES_AGENT_PROMPT.md              # System prompt and Heartbeat protocol specification for Hermes Agent
    └── test_integration.py                 # Integration test (iCloud parsing + MCP tools, no network)
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
- `get_user_location(max_age_minutes=60)`: Returns place name, activity, context summary, suggested conversational opener, coordinates, accuracy, **movement context**, battery, and speed.
- `get_location_history(limit=20)`: Returns recent movement trajectory with resolved places.
- `add_known_place(name, category, latitude, longitude, radius_meters)`: Dynamically registers new places (e.g. gym, home, office).
- `list_known_places()`: Lists all configured places and geofences.

**Movement context — CoreMotion is the "now" signal, GPS answers "where":**
- `motion_activity`: `walking` / `running` / `cycling` / `driving` / `stationary` / `unknown`
  (CoreMotion, refreshed independently of the GPS fix).
- `is_moving_now`: whether he is moving right now (fresh motion wins; otherwise a fresh fix's speed).
- `motion_fresh`: whether the motion reading is recent enough to trust (≤ 5 minutes).
- `is_stale` / `fix_age_minutes` / `minutes_since_last_move`: minutes since GPS last **rewrote** (he last moved ~10 m). A long age at a known place means he is still there.

`get_user_location()` returns a line like `• Movement: walking (CoreMotion, live 12s ago)` or
`• Movement: stationary`. So a stale GPS fix can still say "at the gym" while `motion_activity`
says "walking": trust `is_moving_now` + `motion_activity` for *moving vs staying*, and
`place_name` for *which place*. On the phone, **Motion & Fitness** must be allowed
(`NSMotionUsageDescription` is in `Info.plist`); the Simulator emits no CoreMotion, so
`unknown` there is expected.

The phone writes these fields into `latest_location.json` in the iCloud container:
`motion_activity` (`stationary`/`walking`/`running`/`cycling`/`automotive`/`unknown`),
`motion_confidence` (`high`/`medium`/`low`), and `motion_timestamp` (ISO-8601 UTC).
That file is rewritten only when the GPS coordinate changes; an unchanged position leaves the file (and its timestamp) untouched.

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

---

## 🚀 Running the System

### Step 1: Open and Run the iOS Companion App
1. Open `hermes-companion-ios.xcworkspace` in Xcode:
   ```bash
   open hermes-companion-ios.xcworkspace
   ```
2. Select your iPhone and press **Run (⌘R)**.
3. On first launch:
   - Select **"Allow While Using App"**, then tap the in-app banner to upgrade to **"Always Allow"** in iOS Settings (required by iOS to wake closed apps).
4. Make sure the app is signed into iCloud with the **same Apple ID** as the Mac and the
   `iCloud.com.hermes.HermesCompanion` container is enabled in the provisioning profile,
   so the synced file reaches the Mac's iCloud container.

### Step 2: Verify the Mac-side Reading
macOS syncs the file to
`~/Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/Documents/latest_location.json`.
Confirm it is readable:
```bash
python3 server/scripts/rukara_location.py
```

> **Note on Timestamps & Timezones:** The raw JSON timestamp uses ISO-8601 UTC format (`...Z`). For example, `09:53:05Z` represents `11:53:05` local time in Germany (CEST / UTC+2). All client scripts calculate data freshness relative to `UTC now`, ensuring precise age calculations regardless of local timezones. Because GPS files are write-on-change, a growing `age_seconds` while you stay put is expected: the timestamp is the last movement, not the last GPS radio tick.

### Step 3: Run the Integration Test
Verify the iCloud parsing and the MCP tools (no relay, no network):
```bash
python3 server/test_integration.py
```
