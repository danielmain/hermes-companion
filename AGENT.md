# AGENT.md — Developer & AI Agent Context Guide

> **MANDATORY INSTRUCTION FOR ALL AGENTS:**
> 1. Read this file at the start of every session before making any changes.
> 2. **Functional Programming:** Favor functional programming paradigms, immutability, pure functions, and declarative composition wherever possible.
> 3. **Type-Driven Safety:** Use expressive, rich types (exhaustive enums, structs, Result types) so the compiler surfaces potential bugs early and prevents illegal states.
> 4. **Mandatory Logging:** Implement comprehensive, structured diagnostic logging on every change, state transition, and error.
> 5. **Documentation Maintenance Rule:** On **every change**, you **MUST** update this file (`AGENT.md`) and/or `README.md` if the change warrants it.
> 6. **Mandatory Upstream Fork Sync & Push Rule:** Any modification to the skill files in `skills/hermes-companion/` (`SKILL.md`, `references/`, `scripts/`) **MUST** be synchronized to the official hermes-agent fork at `/Users/daniel/Workspace/hermes-agent/optional-skills/health/hermes-companion/`, verified with tests, and **committed and pushed** to origin `feat/hermes-companion-skill`. Always run `./scripts/sync_hermes_agent.sh "commit message"` to automate this.

---

## 🎯 Project Mission & Context

**Hermes Companion iOS** is an iOS application whose sole purpose is to **reliably transmit the user's live physical location to the Hermes AI Agent framework**, even when the app is in the background, suspended, or **completely closed/terminated by iOS or device reboot**.

The project consists of four pieces:
1. **iOS Native Client (`HermesCompanion/`)**: A Swift/SwiftUI application configured with CoreLocation background modes, significant location change monitoring, stationary perimeter geofencing, and automatic **iCloud/CloudKit sync** of location and Apple Health telemetry.
2. **Hermes Skill (`skills/hermes-companion/`)**: One published skill for place, motion, sleep, workouts, and recovery. `hermes skills install danielmain/hermes-companion/skills/hermes-companion`.
3. **Optional MCP bridge (`server/`)**: Zero-dependency Python MCP server and integration tests that read the same iCloud files. The skill does not require it.
4. **App Store & Documentation Web Presence (`website/`)**: Monochrome editorial Marketing URL (`index.html`), Support URL (`support.html`), and Privacy Declaration (`privacy.html`).

---

## 🏗️ Core Architecture & iOS Lifecycle Engineering

### Why Inbound Calls to iPhone Don't Work
iOS aggressively suspends and terminates apps in the background. An external agent cannot send an inbound HTTP request to an iPhone in a pocket (especially across cellular networks, NAT, and carrier CGNAT). The Mac may be behind NAT too, so there is **no relay server and no direct TCP** path.

### The iCloud/CloudKit Sync Solution
The iOS app writes location and health JSON into its **iCloud/CloudKit ubiquity container**. Apple's iCloud Drive syncs those files down to the Mac, where macOS materialises them on disk (`~/Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/Documents/`). When Hermes Agent needs the user's location, it reads that local file instantly via MCP — **no relay, no open ports, no NAT traversal**.

### GPS Write-On-Change (Movement, Not Indoor Drift)
A GPS fix is persisted only when `GPSPersistDecision` accepts it as movement. Named thresholds live on `TrackingConfiguration`:

- Fresh CoreMotion (`motionSampleReceivedAt` within `motionFreshnessSeconds`, 120 s) of `walking` / `running` / `cycling` / `automotive`: persist when displacement is at least the Standard Distance Filter (`distanceFilterMeters`, default `defaultDistanceFilterMeters` = 30 m, floor 1 m). Reason `moved`.
- Fresh `stationary`: do **not** persist unless displacement is greater than `stationaryUnambiguousDisplacementMeters` (150 m, reason `distance`) or `speed > stationarySpeedOverrideMps` (1 m/s) and displacement still clears the distance filter (reason `moved`). A shorter jump is `stationary_drift` and is refused. Stationary wins over a contradictory GPS fix until the distance is unambiguous.
- No fresh motion sample (typical after the 2-minute window, or in background before a callback): use the distance filter alone. A write is reason `no_motion_reading`; a shorter jump is refused.

The first fix, with no stored anchor, is persisted so the phone has a position to compare against.

Refused ticks do **not** append a `LocationRecord`, rewrite `latest_location.json`, upload a CloudKit location record, or write a diagnostic file. `LocationStore.saveRecord` still returns `false` without touching disk when the latest stored coordinate is inside the threshold it was given. `CloudKitSyncManager.mirrorLatestLocationToFile` still refuses an identical coordinate. The timestamp in `latest_location.json` is the last **accepted** move. Accepted records carry `movement_reason` (`moved`, `distance`, or `no_motion_reading`) in that JSON file and on the CloudKit record (`movementReason`). `stationary_drift` appears in the unified log line for refusals (`GPS persist skip: … by=movement|distance reason=…`), not in a file.

A stored distance filter of exactly `legacyDistanceFilterMeters` (10 m, the old factory default) is raised to 30 m on launch and saved. Any other slider value is left alone. The Settings slider stays `0...50` m in steps of 5.

CoreMotion `motion_activity` remains the signal for whether the user is moving right now. A growing GPS age at a known place indicates the user was stationary there, provided motion or location telemetry is fresh.
- **Freshness & Staleness Verification:** If the last location fix is older than 30 minutes and no fresh CoreMotion activity has verified stationary status within 30 minutes, `still_there` is set to `False` (`still_there_status: unconfirmed (no fresh ping in Xm)`). This prevents falsely concluding the user is still at a previous location when the iOS app is suspended or delayed in triggering a background update (as documented in `bug.md`).
- **Rolling Location History (`location_history.json`):** Along with `latest_location.json`, the iOS app synchronizes a rolling 7-day archive (up to 1,000 points) to the iCloud container. This stores coordinates, timestamps, accuracy, motion activity, and trigger reasons.
- **Apple Maps Native Reverse Geocoding (`CLGeocoder`):** When movement is persisted, the iOS client reverse-geocodes the coordinates asynchronously using Apple Maps on-device (`CLGeocoder`). Points of interest (POI) and street/city data are written to `placemark_name`, `placemark_locality`, and `placemark_thoroughfare` in `latest_location.json` and `location_history.json`. When a location has no custom match in `places.json`, the Hermes skill automatically falls back to this Apple Maps placemark (tagged as `apple_maps` category). User-configured places in `places.json` always take precedence.
- **Distilled Timeline & In-Memory SQLite:** Raw history JSON is never fed directly to the LLM. Instead, `companion.py --timeline` (or `--sql`) aggregates raw fixes into visits, dwell durations, and detected transit intervals, flagging any telemetry gaps (>30m silence during transit).
- **Bidirectional Known Places Synchronization (`places.json`):** Places created or edited in the iOS app (via the `Places` tab) are written locally and synced to iCloud `Documents/places.json`. Both the Hermes skill (`companion.py`) and the MCP server (`server/places.py`) automatically detect and merge places from the iCloud container with any existing profile places (`state/places.json`). New places configured on the iPhone are instantly available to the AI agent.

### What the agent is told
The repository stays generic: no personal name, no agent persona, no home path, no device id. Voice stays in the agent's own profile.

Skill instructions, `README.md`, and `server/HERMES_AGENT_PROMPT.md` are English because the model reads them. The user-facing reply is in the user's language. Saved place names stay as written. Codes (`home`, `walking`, `In Transit`, `Unlisted place`, `fatigued`) are translated by the agent. `companion.py` and the MCP tools print `facts_only:` key/value lines. They do not emit a sentence to quote. Older health files may still contain `suggested_openers`, `sleep.summary`, or `workout.summary`; the reader logs and drops those fields. New health snapshots omit them.

Neither phone battery percentage nor speed are tracked, stored, or reported. `latest_location.json` and `location_history.json` omit `battery_level`, `battery_state`, and `speed_mps`. The iOS app UI does not display battery or speed, and the skill and MCP server do not report them. If an older file still contains them, the reader ignores those keys.

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

### Timestamps, UTC Standard & Timezone Handling
- **Zulu Time (UTC) Canonical Format:** All timestamps written by the iOS app into `latest_location.json` and `latest_health.json` (as well as CloudKit records) use ISO 8601 with the **`Z`** (Zulu) suffix (e.g. `2026-09-29T09:53:05Z`).
- **Timezone Independence:** Timestamps are recorded in UTC. In a UTC+2 timezone, `09:53:05Z` is `11:53:05` local wall-clock time.
- **Age Calculations:** Server and agent readers (such as `server/client.py` and `server/places.py`) must always calculate fix age by comparing the UTC timestamp directly against `datetime.now(timezone.utc)`. This ensures that relative age (`age_seconds`, `age_human`) is strictly accurate regardless of local daylight savings time, traveler location, or server timezone. GPS files are write-on-change, so a growing fix age while the user stays put is expected: the timestamp is the last movement, not the last GPS radio tick.

### Apple Health & Sleep Telemetry Engine (Zero Double-Counting Architecture)
Apple HealthKit stores category samples from **all devices and applications** (e.g., Apple Watch hardware sensors, iPhone accelerometer/Bedtime schedule, and third-party sleep trackers). Querying `HKCategoryTypeIdentifier.sleepAnalysis` without deduplication returns all concurrent samples, causing raw sums to double or triple sleep hours (e.g., reporting 14h instead of 7h).

To guarantee clinical precision matching Apple Health's official displays, [HealthKitManager.swift](HermesCompanion/Services/HealthKitManager.swift) executes a 4-step pipeline:
1. **Sleep Session Clustering:** Looks back 36 hours, sorts samples by `endDate` descending, and clusters backward from the latest wake-up time. A gap of > 4 hours between contiguous sleep stages defines a boundary, cleanly isolating last night's session from prior naps or previous nights.
2. **Hardware Source Prioritization:** Detects whether sources provide granular hypnogram stages (`asleepDeep`, `asleepREM`, `asleepCore`). Prioritizes Apple Watch first-party sensors (`com.apple.health`) over coarse iPhone estimates (`asleepUnspecified`).
3. **Disjoint Interval Merging (`mergeIntervals`):** Merges all overlapping or duplicate time intervals for each stage (`Deep`, `REM`, `Core`, `Awake`), ensuring no timestamp is ever counted twice.
4. **Union-Based Total Sleep Duration:** Total sleep duration is computed as the duration of the union of all sleep intervals ($\text{Deep} \cup \text{REM} \cup \text{Core}$). This makes it mathematically impossible for sleep time to exceed the physical elapsed time between `bedtime` and `wakeTime`.

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
│   │   ├── HealthSnapshot.swift            # Apple Health metrics snapshot (workouts, heart rate, sleep, steps)
│   │   ├── LocationRecord.swift            # Core location model (coords, accuracy, motion, triggers)
│   │   ├── Place.swift                     # Known place model (name, category, radius, coordinates, activity)
│   │   └── TrackingConfiguration.swift     # Profiles (Smart, Ultra, Battery) and server sync parameters
│   ├── Services/
│   │   ├── BackgroundTaskManager.swift     # BGTaskScheduler registration for refresh & processing
│   │   ├── CloudKitSyncManager.swift       # Apple CloudKit Private DB & Ubiquity container synchronizer
│   │   ├── HealthKitManager.swift          # HealthKit manager querying workouts, sleep, resting HR, and steps
│   │   ├── LocationManager.swift           # CoreLocation manager (significant, geofence, visits, wakeups)
│   │   ├── LocationStore.swift             # Thread-safe persistent JSON store with synchronous loading & iCloud rehydration
│   │   └── PlacesStore.swift               # Known places store synchronized with iCloud places.json
│   ├── Views/
│   │   ├── MainTabView.swift               # 5-tab layout (Today, Health, Places, Archive, Settings)
│   │   ├── DashboardView.swift             # Primary transmitter telemetry UI and architecture guides
│   │   ├── HealthDetailView.swift          # Deep-dive Apple Health telemetry view
│   │   ├── PlacesView.swift                # Places management UI: register/edit home, gym, work with geofences
│   │   ├── HistoryLogView.swift            # Historical transmission stream and diagnostic event logs
│   │   ├── SettingsView.swift              # Pipeline selector (CloudKit), container ID, iOS settings link
│   │   └── Components/
│   │       ├── HealthOverviewCard.swift    # Visual card displaying Apple Health telemetry and permissions
│   │       ├── LocationRowView.swift       # Visual row for individual location fixes with trigger badges
│   │       ├── MetricTileView.swift        # Telemetry stat cards (Accuracy, Wakes, Sync count)
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
├── skills/hermes-companion/                # Published Hermes skill (place + health, one skill)
│   ├── SKILL.md                            # Frontmatter description is the skill-index line
│   ├── references/files.md                 # JSON field notes loaded on demand
│   └── scripts/
│       ├── companion.py                    # Stdlib reader for the iCloud files
│       └── test_companion.py               # Reader checks, no network
└── server/                                 # Optional MCP bridge and integration tests
    ├── places.py                           # Semantic place engine used by the MCP tools
    ├── mcp_server.py                       # MCP server (stdio) resolving places in location & history
    ├── client.py                           # iCloud file reader with SQLite fallback
    ├── skills/README.md                    # Points at the single root skill
    ├── HERMES_AGENT_PROMPT.md              # Generic notes for an agent that reads the files
    └── test_integration.py                 # iCloud parsing + MCP tools, no network
```

### Detailed File Descriptions

#### iOS Application
- [HermesCompanion/App/AppDelegate.swift](HermesCompanion/App/AppDelegate.swift): Crucial entry point. Checks `launchOptions?[.location]` when iOS relaunches the app after termination, immediately binds `LocationManager.shared`, and registers background tasks.
- [HermesCompanion/App/HermesCompanionApp.swift](HermesCompanion/App/HermesCompanionApp.swift): Initializes SwiftUI environment objects and mounts `AppDelegate`.
- [HermesCompanion/Services/LocationManager.swift](HermesCompanion/Services/LocationManager.swift): Central CoreLocation orchestrator. Implements `CLLocationManagerDelegate`. Manages permission state, significant location change monitoring, stationary perimeter geofencing, visit callbacks, and triggers auto-sync. Also runs a `CMMotionActivityManager` for real motion state (stationary/walking/running/cycling/automotive), refreshed independently of the GPS fix. `ingestLocation` persists and syncs a fix only when `GPSPersistDecision` accepts the displacement. Each decision logs one line: displacement, threshold, motion state and age, horizontal accuracy, and whether the gate was movement or distance.
- [HermesCompanion/Services/LocationStore.swift](HermesCompanion/Services/LocationStore.swift): Serializes location records and diagnostic events to JSON files in `Application Support`. Loads data synchronously on initialization (`loadDataSynchronously()`) to prevent race conditions where early location fixes overwrite historical records, and rehydrates from iCloud container `location_history.json` if local store is empty. Provides `recentRecords(withinDays:maxCount:)` with rolling 7-day or 1,000-point retention. Supports exporting to GPX, GeoJSON, and CSV.
- [HermesCompanion/Models/Place.swift](HermesCompanion/Models/Place.swift): Codable model for known user locations (name, extensible `PlaceCategory` struct conforming to `RawRepresentable` and `ExpressibleByStringLiteral`, `tags: [String]` list, custom activity description, coordinates, geofence radius in meters, optional notes). Backwards-compatible with `places.json` schema.
- [HermesCompanion/Services/PlacesStore.swift](HermesCompanion/Services/PlacesStore.swift): Observable store managing user-defined places with immutable functional updates. Synchronizes changes both locally and to iCloud container `Documents/places.json`.
- [HermesCompanion/Views/PlacesView.swift](HermesCompanion/Views/PlacesView.swift): Editorial monochrome UI view for listing, adding, and deleting known places. Features a responsive, multi-line `EditorialFlowLayout` for flexible tag selection, extensible presets (Home, Work, Gym, Café, Outdoors, Park, School, Shop, Transit, General), an inline custom tag creator (e.g. library, parents, bouldering), and "Use Current Fix" coordinate autofill.
- [HermesCompanion/Services/HealthKitManager.swift](HermesCompanion/Services/HealthKitManager.swift): Apple Health orchestrator. Queries workouts, sleep analysis, heart rate, resting heart rate, HRV, active energy, and daily steps. Implements background delivery (`enableBackgroundDelivery`) and `HKObserverQuery`. Features intelligent sleep deduplication: merges overlapping time intervals (`mergeIntervals`), prioritizes Apple Watch hardware stage sources over coarse phone estimates, clusters backward from latest wake time with a 4-hour session gap cutoff, and calculates total sleep as the mathematical union of all sleep stages ($\text{Deep} \cup \text{REM} \cup \text{Core}$) to guarantee zero double-counting across sources.
- [HermesCompanion/Services/HealthKitManager.swift](HermesCompanion/Services/HealthKitManager.swift): Apple Health orchestrator. Queries workouts, sleep analysis, heart rate, resting heart rate, HRV, active energy, and daily steps. Implements background delivery (`enableBackgroundDelivery`) and `HKObserverQuery`. Features intelligent sleep deduplication: merges overlapping time intervals (`mergeIntervals`), prioritizes Apple Watch hardware stage sources over coarse phone estimates, clusters backward from latest wake time with a 4-hour session gap cutoff, and calculates total sleep as the mathematical union of all sleep stages ($\text{Deep} \cup \text{REM} \cup \text{Core}$) to guarantee zero double-counting across sources.
- [HermesCompanion/Models/HealthSnapshot.swift](HermesCompanion/Models/HealthSnapshot.swift): Codable health snapshot: `SleepRecord`, `WorkoutRecord`, and `VitalsRecord`. The file written for the agent carries codes and numbers. English insight sentences are not generated.
- [HermesCompanion/Views/Components/HealthOverviewCard.swift](HermesCompanion/Views/Components/HealthOverviewCard.swift): Visual SwiftUI card mounted on `DashboardView` displaying live sleep hours, workout status, heart rate, recovery pills, HealthKit authorization triggers, and manual refresh sync.
- [HermesCompanion/Services/CloudKitSyncManager.swift](HermesCompanion/Services/CloudKitSyncManager.swift): Manages CloudKit Private Database uploads (`CKModifyRecordsOperation`), diagnostic test pings, and mirrors coordinates into the ubiquitous iCloud container for zero-network macOS file sync. `latest_location.json` is rewritten only when GPS coordinates change (omitting battery and speed). Atomically mirrors `location_history.json` on each sync batch.
- [HermesCompanion/Models/LocationRecord.swift](HermesCompanion/Models/LocationRecord.swift): Codable model capturing coordinates, horizontal/vertical accuracy, course, app lifecycle state, trigger source, CoreMotion activity (`motionActivity`/`motionTimestamp`/`motionConfidence`), optional `movementReason`, and CloudKit `CKRecord` conversions. Decoding tolerates records saved before `movementReason` existed. `GPSPersistDecision.evaluate` is the pure persist gate. Exposes `isUnchangedGPS` / `displacementMeters`.
- [HermesCompanion/Services/BackgroundTaskManager.swift](HermesCompanion/Services/BackgroundTaskManager.swift): Registers `BGAppRefreshTask` and `BGProcessingTask` with `BGTaskScheduler`.
- [HermesCompanion/Models/TrackingConfiguration.swift](HermesCompanion/Models/TrackingConfiguration.swift): Stores user preferences (tracking mode, CloudKit container identifier, geofence radius, distance filter) and the named persist-gate constants (30 m default filter, 150 m stationary override, 1 m/s speed override, 120 s motion freshness, slider 0...50).
- [HermesCompanion/Models/AppDiagnosticEvent.swift](HermesCompanion/Models/AppDiagnosticEvent.swift): Represents system lifecycle logs with severity (`INFO`, `SUCCESS`, `WARN`, `ERROR`).
- [HermesCompanion/Views/MainTabView.swift](HermesCompanion/Views/MainTabView.swift): Root tab view hosting `Transmitter`, `Transmissions`, and `Hermes Config`.
- [HermesCompanion/Views/DashboardView.swift](HermesCompanion/Views/DashboardView.swift): Real-time transmitter dashboard displaying connection state, telemetry tiles, tracking mode selector, recent fixes, and explainer sheets.
- [HermesCompanion/Views/HistoryLogView.swift](HermesCompanion/Views/HistoryLogView.swift): Segmented view for transmission history and diagnostic logs with source filtering, file export, and `LocationDetailView` displaying signal metadata and an interactive `AppleMapsPreviewFrame` that launches Apple Maps on tap.
- [HermesCompanion/Views/SettingsView.swift](HermesCompanion/Views/SettingsView.swift): Configuration screen for the CloudKit sync container ID, geofence radius slider, and iOS settings shortcut.
- [HermesCompanion/Views/Components/ICloudAccountBannerView.swift](HermesCompanion/Views/Components/ICloudAccountBannerView.swift): Banner alerting the user when an iCloud / Apple Account sign-in is required with a direct button redirecting to iOS Settings.
- [HermesCompanion/Resources/Info.plist](HermesCompanion/Resources/Info.plist): Contains Apple background modes (`location`, `fetch`, `processing`, `remote-notification`), background task identifiers, `NSUbiquitousContainers`, required location usage descriptions, `NSMotionUsageDescription` (CoreMotion activity), `NSHealthShareUsageDescription`, and `NSHealthUpdateUsageDescription`.
- [HermesCompanion/Resources/HermesCompanion.entitlements](HermesCompanion/Resources/HermesCompanion.entitlements): Declares iCloud container `iCloud.com.hermes.HermesCompanion` for `CloudKit` and `CloudDocuments`, and `com.apple.developer.healthkit` capability.

#### Server & Agent Integration
- [server/places.py](server/places.py): Place recognition. Matches the fix to a named place in the user's places file (`HERMES_COMPANION_PLACES`, `HERMES_HOME/state/places.json`, or the only Hermes profile that already has one). Internal `context_summary` strings stay for the resolver tests. The skill and MCP tools do not present them as lines to say.
- [skills/hermes-companion/SKILL.md](skills/hermes-companion/SKILL.md): The single published Hermes skill (version 1.2.0). Replaces `user-location` and `user-health`. Frontmatter follows the skill authoring format (`name`, `description` under 60 characters, `version`, `author`, `license`, `platforms`, `metadata.hermes.tags`, `category: health`, and `config`). The description and the Requires the iPhone app section say the skill works only with this iOS app. Product page: https://hermescompanion.funktional.dev. Install with `hermes skills install danielmain/hermes-companion/skills/hermes-companion`. The Language section tells the model to answer in the user's language. A pull request into Hermes Agent belongs at `optional-skills/health/hermes-companion/`, which is the skill directory only.
- [skills/hermes-companion/scripts/companion.py](skills/hermes-companion/scripts/companion.py): Stdlib reader. Resolves known places, checks freshness, and prints key/value facts (`place_name`, `still_there`, motion freshness, `movement_reason`, health codes). Flags stale fixes without fresh motion as `still_there: unconfirmed`. Reads rolling history via `--timeline` (summarizing stays, dwell times, transits, and telemetry gaps) or executes in-memory SQL queries via `--sql`. Logs `INFO` / `WARN` / `ERROR` on stderr.
- [server/mcp_server.py](server/mcp_server.py): Model Context Protocol (MCP) server communicating over stdio (JSON-RPC). Exposes `get_user_location`, `get_user_health`, `get_user_physical_context`, `get_location_history`, `add_known_place`, and `list_known_places`. Reads from both local SQLite cache and iCloud `location_history.json`.
- [server/client.py](server/client.py): Python helper for direct zero-network reading of location, rolling location history (sorted descending by timestamp, returning the newest waypoints up to `limit`), and Apple Health telemetry from the locally synced iCloud/CloudKit files, falling back to the local SQLite cache.
- [server/HERMES_AGENT_PROMPT.md](server/HERMES_AGENT_PROMPT.md): Generic notes for an agent that reads location and health. Personal voice stays in the agent's own profile, not in this repository.
- [server/test_integration.py](server/test_integration.py): Integration test verifying iCloud/CloudKit file parsing (location + health) and MCP tool execution with place resolution, with no relay or network.

---

## 🛠️ Build, Test, and Execution Commands

### Regenerate Xcode Project (After adding/removing files)
```bash
xcodegen generate
```

### Build and Sign for a Physical iPhone
Signing is automatic. Choose your Apple Development team in Xcode under Signing & Capabilities. The team id is not stored in this repository.

```bash
xcodebuild -project HermesCompanion.xcodeproj -scheme HermesCompanion -destination 'platform=iOS,name=YOUR_IPHONE' build
```

### Build for iOS Simulator (CI / Verification)
```bash
xcodebuild -project HermesCompanion.xcodeproj -scheme HermesCompanion -sdk iphonesimulator -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" clean build
```

### Run Python Integration Tests (Uses isolated temporary DB)
```bash
python3 server/test_integration.py
python3 skills/hermes-companion/scripts/test_companion.py
```

---

## 🧩 Engineering Standards: Functional, Typed & Logged

To ensure the codebase is robust, easily testable, and catches bugs at compile-time rather than runtime, all future changes must adhere strictly to these three engineering pillars:

### 1. Functional Programming as Much as Possible
- **Immutability First:** Prefer immutable structures (`let`) by default. Avoid mutable shared state unless explicitly required by framework lifecycle constraints.
- **Pure Functions & Determinism:** Separate business logic and calculations (e.g., distance calculations, age formatting, payload transformations, filtering) into pure, side-effect-free functions that are trivial to unit test.
- **Declarative Composition:** Utilize functional pipelines (`map`, `flatMap`, `compactMap`, `filter`, `reduce`) over imperative loops and mutating state accumulators.
- **Isolate Side Effects:** Keep side-effects (CoreLocation delegate callbacks, disk I/O, iCloud sync, `BGTaskScheduler`) strictly isolated to service boundaries (`LocationManager`, `LocationStore`, `CloudKitSyncManager`).

### 2. Rich, Expressive Type-Driven Design
- **Make Illegal States Unrepresentable:** Use the type system as the first line of defense. The compiler must catch structural errors before code ever runs.
- **Eliminate Stringly-Typed Code:** Never pass raw arbitrary strings for domain concepts (e.g. app states, trigger types, error codes, HTTP statuses). Model them as exhaustive Swift `enum`s with associated values or raw values with `CaseIterable` and `Identifiable`.
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
4. **Maps Restricted to Explicit User Request:** The transmitter engine itself remains lightweight without heavy live maps in the telemetry dashboard. Per user request, the record detail inspector (`LocationDetailView`) embeds a small Apple Maps preview frame (`AppleMapsPreviewFrame`) for inspecting individual historical fixes, which opens Apple Maps when clicked/tapped.
5. **Preserve Closed-State Wakeup Guarantees:**
   - Do **NOT** remove or delay `LocationManager.shared` initialization in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
   - Do **NOT** remove `location` from `UIBackgroundModes` in `Info.plist`.
   - Do **NOT** remove `startMonitoringSignificantLocationChanges()` or stationary geofencing, as standard continuous GPS does NOT survive a user swipe-kill or OS memory purge on iOS.
6. **XcodeGen as Source of Truth:** Do not edit `.xcodeproj` files manually. Make project structure or build setting changes in `project.yml`, then run `xcodegen generate`.
7. **Verify Builds Before Completion:** Always ensure `xcodebuild` succeeds and `python3 server/test_integration.py` passes before finalizing work.
8. **GPS Write-On-Change:** Do not reintroduce writes of `location_records.json`, `latest_location.json`, CloudKit location records, or diagnostic files for a GPS tick `GPSPersistDecision` refuses. A fresh stationary CoreMotion sample blocks the write until displacement passes 150 m or speed passes 1 m/s (and the distance filter). With no fresh motion sample, the tick must move at least the Standard Distance Filter (default 30 m, floor 1 m). A fresh walking, running, cycling, or automotive sample uses that same filter. Refused ticks must leave every GPS file untouched. Do not lower `unchangedPositionThresholdMeters` or the distance-filter default back to 10 m: indoor drift crosses 10 m while the user is still at home.
9. **Keep the repository generic:** Do not commit personal names, home directory paths, device UDIDs, Apple Team IDs, or certificate identifiers. Signing stays in Xcode on each machine. Agent voice stays in the agent's own profile.
10. **Any language, no quoted English, no battery or speed for agent or app:** Skill text stays English. Replies are in the user's language. Do not add English sentences (`suggested_greeting`, insights, openers, summaries) for the agent to recite. Neither the agent nor the app tracks or displays battery percentage or speed. Do not reintroduce `battery_level`, `battery_state`, `speed_mps`, or `speed_kmh` into `latest_location.json`, `location_history.json`, `LocationRecord`, or UI screens.
11. **Mandatory Synchronization with Hermes Agent Fork:** Any changes made to the Hermes Companion skill files in `skills/hermes-companion/` (`SKILL.md`, `references/files.md`, `scripts/companion.py`, `scripts/test_companion.py`) **MUST** be synced and committed to the corresponding folder in the `hermes-agent` fork located at `/Users/daniel/Workspace/hermes-agent/optional-skills/health/hermes-companion/`.
    - Run `./scripts/sync_hermes_agent.sh "feat(skills): ..."` to automate syncing, test execution in the fork, and git commit/push to origin `feat/hermes-companion-skill`.
    - Always ensure the fork branch `feat/hermes-companion-skill` stays in lockstep with every skill change in this repository.


