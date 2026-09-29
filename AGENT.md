# AGENT.md — Developer & AI Agent Context Guide

> **MANDATORY INSTRUCTION FOR ALL AGENTS:**
> 1. Read this file at the start of every session before making any changes.
> 2. **Functional Programming:** Favor functional programming paradigms, immutability, pure functions, and declarative composition wherever possible.
> 3. **Type-Driven Safety:** Use expressive, rich types (exhaustive enums, structs, Result types) so the compiler surfaces potential bugs early and prevents illegal states.
> 4. **Mandatory Logging:** Implement comprehensive, structured diagnostic logging on every change, state transition, and error.
> 5. **Documentation Maintenance Rule:** On **every change**, you **MUST** update this file (`AGENT.md`) and/or `README.md` if the change warrants it.

---

## 🎯 Project Mission & Context

**Hermes Companion iOS** is an iOS application whose sole purpose is to **reliably transmit the user's live physical location to the Hermes AI Agent framework**, even when the app is in the background, suspended, or **completely closed/terminated by iOS or device reboot**.

The project consists of two tightly coupled components:
1. **iOS Native Client (`HermesCompanion/`)**: A Swift/SwiftUI application configured with CoreLocation background modes, significant location change monitoring, stationary perimeter geofencing, and automatic HTTP telemetry syncing.
2. **Hermes Ingestion & Agent Bridge (`server/`)**: A zero-dependency Python relay server with SQLite persistence, a native Model Context Protocol (MCP) server, and integration tests.

---

## 🏗️ Core Architecture & iOS Lifecycle Engineering

### Why Inbound Calls to iPhone Don't Work
iOS aggressively suspends and terminates apps in the background. An external agent cannot send an inbound HTTP request to an iPhone in a pocket (especially across cellular networks, NAT, and carrier CGNAT).

### The Push-and-Query Solution
Instead, the iOS app acts as an autonomous background transmitter. Whenever movement occurs, it wakes up and pushes coordinates to a local or remote relay. When Hermes Agent needs the user's location, it queries the relay instantly (<2ms) via MCP or REST.

### Tri-Layer "Always-On Even When Closed" Engine
1. **Significant Location Change Service (`startMonitoringSignificantLocationChanges`)**:
   - Monitored at cell-tower / Wi-Fi transition level (~500m movement).
   - When triggered, iOS **automatically wakes or relaunches the terminated app in the background**.
   - **Critical App Lifecycle Contract:** iOS delivers `UIApplication.LaunchOptionsKey.location` in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`. `LocationManager.shared` is instantiated immediately at launch so CoreLocation delegate receives and handles the pending location event.
2. **Stationary Dynamic Perimeter Geofencing (`CLCircularRegion`)**:
   - When stationary (<1 m/s), a rolling circular geofence (default 100m) is established.
   - If the app is closed, crossing this perimeter triggers `locationManager(_:didExitRegion:)`, prompting iOS to wake the app from its closed state and resume active tracking.
3. **Visits Monitoring Service (`startMonitoringVisits`)**:
   - Uses Apple's CoreLocation Visit Detection to wake up and record arrival and departure times at frequent destinations.
4. **Continuous Standard GPS (`allowsBackgroundLocationUpdates = true`)**:
   - High-precision tracking while moving or while active in foreground/background.

---

## 🗺️ Project File Map & Component Directory

```text
hermes-companion-ios/
├── AGENT.md                                # This file: Session guide, file map, and development rules
├── README.md                               # User documentation, setup guide, and API reference
├── project.yml                             # XcodeGen specification (build settings, sources, bundle ID)
├── hermes-companion-ios.xcworkspace/       # Xcode workspace container
│   └── contents.xcworkspacedata            # Workspace mapping referencing HermesCompanion.xcodeproj
├── HermesCompanion.xcodeproj/              # Generated Xcode project (managed by XcodeGen)
├── .gitignore                              # Git ignore rules for Xcode, DerivedData, and SQLite
├── HermesCompanion/                        # Main iOS application source directory
│   ├── App/
│   │   ├── AppDelegate.swift               # Handles launchOptions[.location] for closed-state wakeups
│   │   └── HermesCompanionApp.swift        # SwiftUI App root with @UIApplicationDelegateAdaptor
│   ├── Models/
│   │   ├── AppDiagnosticEvent.swift        # Diagnostic log model (severity, timestamp, message)
│   │   ├── LocationRecord.swift            # Core location model (coords, accuracy, speed, battery, triggers)
│   │   └── TrackingConfiguration.swift     # Profiles (Smart, Ultra, Battery) and server sync parameters
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
│   │   ├── SettingsView.swift              # Pipeline selector (CloudKit / Webhook), container ID, iOS settings link
│   │   └── Components/
│   │       ├── LocationRowView.swift       # Visual row for individual location fixes with trigger badges
│   │       ├── MetricTileView.swift        # Telemetry stat cards (Accuracy, Battery, Wakes, Sync count)
│   │       ├── PermissionBannerView.swift  # Dynamic alert guiding user to grant "Always Allow" in Settings
│   │       ├── ICloudAccountBannerView.swift # Dynamic alert guiding user to sign in to Apple ID / iCloud
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
    ├── relay.py                            # Zero-dependency Python HTTP relay with SQLite persistence & places API
    ├── mcp_server.py                       # Model Context Protocol (MCP) server for Hermes Agent (stdio)
    ├── client.py                           # Python client module (iCloud, SQLite, & HTTP relay fallbacks + context)
    ├── scripts/
    │   └── rukara_location.py              # CLI helper installed into love profile (scripts/rukara_location.py)
    ├── skills/
    │   └── user-location/
    │       └── SKILL.md                    # Hermes agent skill for location awareness & conversational context
    ├── HERMES_AGENT_PROMPT.md              # System prompt and Heartbeat protocol specification for Hermes Agent
    └── test_integration.py                 # End-to-end integration test (ping, upload, REST fetch, MCP, iCloud)
```

### Detailed File Descriptions

#### iOS Application
- [HermesCompanion/App/AppDelegate.swift](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/App/AppDelegate.swift): Crucial entry point. Checks `launchOptions?[.location]` when iOS relaunches the app after termination, immediately binds `LocationManager.shared`, and registers background tasks.
- [HermesCompanion/App/HermesCompanionApp.swift](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/App/HermesCompanionApp.swift): Initializes SwiftUI environment objects and mounts `AppDelegate`.
- [HermesCompanion/Services/LocationManager.swift](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/Services/LocationManager.swift): Central CoreLocation orchestrator. Implements `CLLocationManagerDelegate`. Manages permission state, significant location change monitoring, stationary perimeter geofencing, visit callbacks, battery monitoring, and triggers auto-sync.
- [HermesCompanion/Services/LocationStore.swift](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/Services/LocationStore.swift): Serializes location records and diagnostic events to JSON files in `Application Support`. Supports exporting to GPX, GeoJSON, and CSV.
- [HermesCompanion/Services/SyncManager.swift](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/Services/SyncManager.swift): Handles HTTP POST communication with the relay server. Batches unsynced records, manages Bearer authentication, and handles ping tests.
- [HermesCompanion/Services/CloudKitSyncManager.swift](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/Services/CloudKitSyncManager.swift): Manages CloudKit Private Database uploads (`CKModifyRecordsOperation`), diagnostic test pings, and mirrors coordinates into the ubiquitous iCloud container for zero-network macOS file sync.
- [HermesCompanion/Services/BackgroundTaskManager.swift](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/Services/BackgroundTaskManager.swift): Registers `BGAppRefreshTask` and `BGProcessingTask` with `BGTaskScheduler`.
- [HermesCompanion/Models/LocationRecord.swift](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/Models/LocationRecord.swift): Codable model capturing coordinates, horizontal/vertical accuracy, speed, course, battery level/state, app lifecycle state, trigger source, and CloudKit `CKRecord` conversions.
- [HermesCompanion/Models/TrackingConfiguration.swift](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/Models/TrackingConfiguration.swift): Stores user preferences (tracking mode, server URL, auth token, geofence radius, distance filter).
- [HermesCompanion/Models/AppDiagnosticEvent.swift](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/Models/AppDiagnosticEvent.swift): Represents system lifecycle logs with severity (`INFO`, `SUCCESS`, `WARN`, `ERROR`).
- [HermesCompanion/Views/MainTabView.swift](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/Views/MainTabView.swift): Root tab view hosting `Transmitter`, `Transmissions`, and `Hermes Config`.
- [HermesCompanion/Views/DashboardView.swift](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/Views/DashboardView.swift): Real-time transmitter dashboard displaying connection state, telemetry tiles, tracking mode selector, recent fixes, and explainer sheets.
- [HermesCompanion/Views/HistoryLogView.swift](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/Views/HistoryLogView.swift): Segmented view for transmission history and diagnostic logs with source filtering and file export.
- [HermesCompanion/Views/SettingsView.swift](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/Views/SettingsView.swift): Configuration screen for transmission destination (CloudKit Private DB / HTTP Webhook / Dual), CloudKit container ID, Bearer API key, geofence radius slider, and iOS settings shortcut.
- [HermesCompanion/Views/Components/ICloudAccountBannerView.swift](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/Views/Components/ICloudAccountBannerView.swift): Banner alerting the user when an iCloud / Apple Account sign-in is required with a direct button redirecting to iOS Settings.
- [HermesCompanion/Resources/Info.plist](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/Resources/Info.plist): Contains Apple background modes (`location`, `fetch`, `processing`, `remote-notification`), background task identifiers, `NSUbiquitousContainers`, and required location usage descriptions.
- [HermesCompanion/Resources/HermesCompanion.entitlements](file:///Users/daniel/Workspace/hermes-companion-ios/HermesCompanion/Resources/HermesCompanion.entitlements): Declares iCloud container `iCloud.com.hermes.HermesCompanion` for `CloudKit` and `CloudDocuments`.

#### Server & Agent Integration
- [server/places.py](file:///Users/daniel/Workspace/hermes-companion-ios/server/places.py): Semantic place & activity recognition engine. Resolves Daniel's physical context (e.g. at the gym, at home, at work, in transit) using radius geofencing over known places stored in `~/.hermes/profiles/love/state/places.json` and cached reverse geocoding with natural conversational greeting generation.
- [server/scripts/rukara_location.py](file:///Users/daniel/Workspace/hermes-companion-ios/server/scripts/rukara_location.py): CLI tool installed in `~/.hermes/profiles/love/scripts/rukara_location.py` to inspect live physical context and manage places in `~/.hermes/profiles/love/state/places.json`.
- [server/skills/user-location/SKILL.md](file:///Users/daniel/Workspace/hermes-companion-ios/server/skills/user-location/SKILL.md): Official Hermes Agent skill installed into `~/.hermes/profiles/love/skills/user-location` enabling natural conversation regarding where Daniel is and what he is doing.
- [server/bridge/HermesCloudKitBridge.swift](file:///Users/daniel/Workspace/hermes-companion-ios/server/bridge/HermesCloudKitBridge.swift): Native macOS Swift CLI tool. Directly queries the user's private CloudKit database for `latest_user_location` or location history and supports daemon mode.
- [server/relay.py](file:///Users/daniel/Workspace/hermes-companion-ios/server/relay.py): Standalone Python HTTP relay server. Runs on port 8080. Ingests location payloads via `POST /api/location`, persists to SQLite (`locations.sqlite3`), serves `GET /api/location/latest` (enriched with semantic context), `GET /api/location/history`, and `GET/POST /api/places`.
- [server/mcp_server.py](file:///Users/daniel/Workspace/hermes-companion-ios/server/mcp_server.py): Model Context Protocol (MCP) server communicating over stdio (JSON-RPC). Exposes `get_user_location` (enriched with place name, activity, context summary, and suggested opener), `get_location_history`, `add_known_place`, and `list_known_places` tools directly to Hermes Agent.
- [server/client.py](file:///Users/daniel/Workspace/hermes-companion-ios/server/client.py): Python helper function supporting direct zero-network reading from local iCloud ubiquitous synced files, falling back to local SQLite and HTTP relay with automatic semantic context enrichment.
- [server/HERMES_AGENT_PROMPT.md](file:///Users/daniel/Workspace/hermes-companion-ios/server/HERMES_AGENT_PROMPT.md): Production-ready system prompt, activity awareness guidelines, and autonomous 5-step Heartbeat protocol specification for Hermes Agent (configured for profile `/Users/daniel/.hermes/profiles/love`).
- [server/test_integration.py](file:///Users/daniel/Workspace/hermes-companion-ios/server/test_integration.py): End-to-end integration test verifying the relay server, iOS ping, payload ingestion, REST querying, MCP tool execution with place resolution, and iCloud file parsing.

---

## 🛠️ Build, Test, and Execution Commands

### Regenerate Xcode Project (After adding/removing files)
```bash
xcodegen generate
```

### Build iOS App with xcodebuild
```bash
xcodebuild -project HermesCompanion.xcodeproj -scheme HermesCompanion -sdk iphonesimulator -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" clean build
```

### Run Python Integration Tests
```bash
python3 server/test_integration.py
```

### Start the Location Relay Server
```bash
python3 server/relay.py --port 8080
```

---

## 🧩 Engineering Standards: Functional, Typed & Logged

To ensure the codebase is robust, easily testable, and catches bugs at compile-time rather than runtime, all future changes must adhere strictly to these three engineering pillars:

### 1. Functional Programming as Much as Possible
- **Immutability First:** Prefer immutable structures (`let`) by default. Avoid mutable shared state unless explicitly required by framework lifecycle constraints.
- **Pure Functions & Determinism:** Separate business logic and calculations (e.g., distance calculations, age formatting, payload transformations, filtering) into pure, side-effect-free functions that are trivial to unit test.
- **Declarative Composition:** Utilize functional pipelines (`map`, `flatMap`, `compactMap`, `filter`, `reduce`) over imperative loops and mutating state accumulators.
- **Isolate Side Effects:** Keep side-effects (CoreLocation delegate callbacks, disk I/O, network requests, `BGTaskScheduler`) strictly isolated to service boundaries (`LocationManager`, `LocationStore`, `SyncManager`).

### 2. Rich, Expressive Type-Driven Design
- **Make Illegal States Unrepresentable:** Use the type system as the first line of defense. The compiler must catch structural errors before code ever runs.
- **Eliminate Stringly-Typed Code:** Never pass raw arbitrary strings for domain concepts (e.g. app states, trigger types, battery states, error codes, HTTP statuses). Model them as exhaustive Swift `enum`s with associated values or raw values with `CaseIterable` and `Identifiable`.
- **Exhaustive Pattern Matching:** Avoid `default:` in `switch` statements whenever possible so adding a new case produces a compile-time check across the entire application.
- **Typed Errors & Results:** Use Swift's `Result<Success, Failure>` or strictly typed `Error` enums instead of discarding errors with loose `try?` where diagnostics matter.
- **Precise Domain Models:** Use value types (`struct`) with exact properties and typed wrappers rather than untyped dictionaries or loose key-value blobs.

### 3. Proper Logging Implemented on Every Change
- **Every Change Warrants Traceability:** Any modification, state transition, background task execution, closed-state wakeup, geofence boundary event, or network call **MUST** include clear, structured logging.
- **Severity-Tagged Diagnostics:** Log events with appropriate severity levels:
  - `INFO`: Routine lifecycle events (e.g., app moved to foreground, geofence deployed, periodic ping scheduled).
  - `SUCCESS`: Meaningful accomplishments (e.g., app successfully woke from closed state, location batch uploaded, permission granted).
  - `WARN`: Recoverable anomalies (e.g., location permission downgraded, geofence expired, network retry needed).
  - `ERROR`: Failures requiring attention (e.g., network failure, CoreLocation denial, JSON parse failure).
- **Dual-Channel Diagnostics:**
  - System logs via `os.Logger` or unified logging.
  - In-app diagnostic history via `LocationStore.shared.logDiagnostic(title:details:severity:)` so that users and developers can audit background wakeups on-device without an attached debugger.

---

## 📋 Rules for Future Agents

1. **MANDATORY DOCUMENTATION UPDATE:** Whenever modifying or adding features, architecture, endpoints, or files, you **MUST** update `AGENT.md` and `README.md` to reflect the changes (if the change warrants it).
2. **Functional & Type-Driven by Default:** Write functional, immutable code. Use rich, expressive types (exhaustive enums, structs, Result types) so the compiler exposes potential bugs early.
3. **Proper Logging on Every Change:** Every newly introduced logic branch, background event, network interaction, or error condition must be accompanied by structured diagnostic logging.
4. **Never Reintroduce Maps Without User Request:** The user explicitly instructed: *"no need for maps, this app only goal is to pass hermes agent the location of the user"*. Keep the app focused as a clean, high-performance location transmitter.
5. **Preserve Closed-State Wakeup Guarantees:**
   - Do **NOT** remove or delay `LocationManager.shared` initialization in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
   - Do **NOT** remove `location` from `UIBackgroundModes` in `Info.plist`.
   - Do **NOT** remove `startMonitoringSignificantLocationChanges()` or stationary geofencing, as standard continuous GPS does NOT survive a user swipe-kill or OS memory purge on iOS.
6. **XcodeGen as Source of Truth:** Do not edit `.xcodeproj` files manually. Make project structure or build setting changes in `project.yml`, then run `xcodegen generate`.
7. **Verify Builds Before Completion:** Always ensure `xcodebuild` succeeds and `python3 server/test_integration.py` passes before finalizing work.
