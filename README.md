<p align="center">
  <img src="assets/icon-source.png" alt="Hermes Companion" width="280">
</p>

<h1 align="center">Hermes Companion</h1>

<p align="center">
  An iPhone app and one Hermes skill.<br>
  Live place, motion, sleep, and workouts — through your own iCloud, with no relay server.
</p>

<p align="center">
  <a href="https://hermes-agent.nousresearch.com/docs/developer-guide/creating-skills">Hermes skill</a>
  &nbsp;·&nbsp;
  <a href="skills/hermes-companion/SKILL.md">SKILL.md</a>
  &nbsp;·&nbsp;
  <a href="LICENSE">MIT</a>
</p>

---

The phone is in a pocket, often on cellular, often with the app swiped away. Nothing on the internet can open a connection to it. Hermes Companion lets iOS wake the app, writes JSON files into the app's private iCloud container, and lets the Hermes agent on your Mac read the copies macOS has already synced.

```
iPhone  →  iCloud Drive  →  Mac disk  →  Hermes skill
                latest_location.json
                location_history.json
                latest_health.json
```

No account with us. No analytics. No open port. The files stay in your Apple ID.

<p align="center">
  <img src="assets/lilith-black.png" alt="" width="720">
</p>

## What the agent can say

| It knows | Because |
| --- | --- |
| You are still at Home | The location file is rewritten only when a move is accepted. Fresh stationary motion confirms you are still there; if telemetry is silent for hours without pings, it reports unconfirmed. |
| Visits, dwell times & trips | `location_history.json` records rolling move history, allowing the skill to compute exact arrival, departure, and stay times. |
| You are walking, not driving | CoreMotion reports `stationary`, `walking`, `running`, `cycling`, or `automotive` on its own clock. |
| You did not just arrive | A new file means the persist gate accepted a displacement. It does not mean you got home. |
| How you slept and trained | HealthKit sleep is the union of Deep, REM, and Core, so Watch and iPhone samples are not added twice. |

Indoor drift of about 10 m while you are still does not rewrite the file. Fresh walking, running, cycling, or driving is stored at 30 m. A fresh stationary reading is stored only past 150 m, or when GPS speed is above 1 m/s and the 30 m filter is also cleared.

Health (sleep, workouts, steps) is written when Apple Health delivers a new sample and on background refresh, not on every GPS tick.

## Language

Skill instructions are English because the model reads them. The agent answers in the language of the conversation: Spanish, German, or any other. A saved place name stays as written (`Casa`, `Home`, `Arbeit`). Codes such as `home`, `walking`, `In Transit`, and `fatigued` are translated in the reply. The script prints facts. It does not hand the agent an English sentence to quote.

## What the agent and app do not track

Phone battery percentage and speed are neither displayed in the app nor reported to the agent. `latest_location.json` and `location_history.json` omit battery and speed, and the UI contains no battery or speed readouts. Older files that may still contain `battery_level` or `speed_mps` are ignored.

This repository has no personal name and no agent persona. Voice and schedule stay in the agent's own profile.

## Install the skill

The skill is `skills/hermes-companion` in this repository. One skill covers place and health. It reads the files this iPhone app writes. With the app uninstalled, or before iCloud has synced, the script reports that no file exists.

Product page: [hermescompanion.funktional.dev](https://hermescompanion.funktional.dev).

```bash
hermes skills install danielmain/hermes-companion/skills/hermes-companion
```

Or keep the repo as a tap and install from it:

```bash
hermes skills tap add danielmain/hermes-companion
hermes skills search hermes-companion
```

Then ask where you are, how you slept, or whether you are still at a place you named. The agent runs:

```bash
python3 ${HERMES_SKILL_DIR}/scripts/companion.py
python3 ${HERMES_SKILL_DIR}/scripts/companion.py --timeline
python3 ${HERMES_SKILL_DIR}/scripts/companion.py --health
python3 ${HERMES_SKILL_DIR}/scripts/companion.py --inbox
python3 ${HERMES_SKILL_DIR}/scripts/companion.py --inbox --pending
python3 ${HERMES_SKILL_DIR}/scripts/companion.py --thread <thread_id>
python3 ${HERMES_SKILL_DIR}/scripts/companion.py --reply <thread_id> --message "..."
```

**Hermes Post / Inbox**: Send and receive asynchronous letters and memos via the in-app **Post** tab. Designed like a private postbox rather than an instant messenger, you can drop an inquiry or briefing to any of your configured agent profiles (`work`, `fitness`, `personal`). Your agent reads the thread on your Mac, consults your physical telemetry, and writes a reply back to your inbox via your own iCloud container (`threads/<thread_id>/messages/`). When using multiple Hermes profiles (`--profile <name>`), each profile automatically registers into `Documents/profiles.json`, allowing you to choose which agent profile to address before sending.

Name the places you care about once. You can register and edit places directly from the iPhone app's **Places** tab (with 1-tap "Use Current Fix", custom tags, and geofence radius) or via the CLI. Both sync automatically via iCloud:

```bash
python3 ${HERMES_SKILL_DIR}/scripts/companion.py --list
python3 ${HERMES_SKILL_DIR}/scripts/companion.py --add \
  --name "Home" --category home --lat LAT --lon LON --radius 120
```

Optional paths, if your container or places file live somewhere else:

```bash
hermes config set skills.config.hermes-companion.places_file ~/places.json
hermes config set skills.config.hermes-companion.icloud_dir \
  "$HOME/Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/Documents"
```

## Install the iPhone app

1. Open `hermes-companion-ios.xcworkspace` in Xcode (or install via App Store when released).
2. If building from source, choose your own Apple Development team under Signing & Capabilities.
3. Allow Location, then upgrade it to **Always** from the in-app banner. Background wakes do not run on While Using.
4. Allow Motion & Fitness and Apple Health.
5. Use the same Apple ID on the phone and the Mac, with iCloud Drive on.

The app keeps working after you leave it, and after iOS relaunches it, through three wake paths plus normal GPS while you are moving:

- Significant location changes, about a cell-tower step, which relaunch a terminated app.
- A stationary geofence (default 100 m) that fires when you leave.
- Visit monitoring for arrivals and departures.
- Standard GPS while the app is active, plus scheduled background processing tasks.

The in-app Archive (accessible from the Today tab) indexes every recorded fix and system event. Tapping any record displays its precise coordinates, instrument telemetry, and an interactive Apple Maps preview frame; tapping the frame launches Apple Maps directly at that coordinate.

Confirm the Mac can see a fix:

```bash
python3 skills/hermes-companion/scripts/companion.py
```

`source:` should be a file under `~/Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/Documents/`.

Timestamps in the JSON are UTC (`2026-10-01T09:53:05Z`). The script compares them to UTC now, so the age is right in any timezone. A growing age while you stay put is the design: the timestamp is the last accepted move, not the last GPS tick.

### System Requirements & Pre-Flight Diagnostics (`--doctor`)

Hermes Companion communicates directly through your private iCloud Drive container, requiring no intermediary relay server or network port. This introduces specific system requirements:

#### 1. Hard Environmental Requirements
- **macOS Host OS (Strict):** Hermes must run directly on the macOS host under your user account — **not inside Docker, WSL, or a remote Linux VM**. Apple's native CloudDocs daemon (`bird`) mirrors iCloud files strictly into macOS `~/Library/Mobile Documents/`. Containerized environments cannot sync iCloud Drive.
- **Shared Apple ID & iCloud Drive:** The iPhone and the Mac must be signed into the same Apple ID with iCloud Drive turned on.
- **First-Run Sequence:** Launch the iPhone app at least once and allow permissions before querying telemetry from the Mac. Apple's cloud daemon provisions the local container on macOS (`~/Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/`) only after the iPhone writes its initial record.
- **Hermes CLI Discovery & PATH:** When the background LaunchAgent auto-dispatches replies to pending letters in Hermes Post, it invokes the Hermes CLI (`hermes chat ...`). The executable must be discoverable across PATH or standard candidate locations:
  - Homebrew: `/opt/homebrew/bin/hermes` or `/usr/local/bin/hermes`
  - Python / Pipx / Cargo: `~/.local/bin/hermes`, `~/.cargo/bin/hermes`, or `~/.hermes/bin/hermes`
  - Hermes macOS Desktop App: `/Applications/Hermes.app/Contents/MacOS/hermes` or `~/Applications/Hermes.app/Contents/MacOS/hermes`

#### 2. Pre-Flight Verification Tool (`--doctor`)
Run the built-in diagnostic tool to test your environment and inspect container state:

```bash
python3 skills/hermes-companion/scripts/companion.py --doctor
```

The doctor command verifies:
1. **Operating System:** Validates macOS host and ensures process is not containerized.
2. **iCloud Drive:** Verifies `~/Library/Mobile Documents` exists and has active TCC permissions.
3. **App Container:** Confirms the container directory is synced and writable, listing currently synchronized files.
4. **Hermes CLI Discovery:** Confirms the `hermes` binary is present and executable.
5. **Background Auto-Responder:** Checks if the LaunchAgent service (`ai.hermes.companion-inbox`) is loaded and running.

If any check fails (such as the container not being provisioned yet, or missing permissions in *System Settings → Privacy & Security → Files and Folders*), actionable remediation steps are printed immediately.

## Letters from the phone (Hermes Post)

Letters written in the app's Post tab land in `Documents/threads/<thread_id>/` as an immutable `meta.json` plus numbered letter files. The Mac answers them on its own: the LaunchAgent `ai.hermes.companion-inbox` keeps `companion.py --daemon` resident and sweeps the container every 5 seconds.

```bash
python3 skills/hermes-companion/scripts/companion.py --install-service
python3 skills/hermes-companion/scripts/companion.py --service-status
python3 skills/hermes-companion/scripts/companion.py --dispatch-pending   # one sweep, foreground
```

The agent is resident rather than a one-shot timer on purpose: a job that exits in milliseconds is throttled by `launchd`, which is what made answers arrive minutes late. If the agent cannot answer a letter, the thread is marked `failed` with `last_error` and `failed_at`, and the app shows that reason with a Retry that puts the letter back in the queue. Logs are timestamped in `~/.hermes/logs/companion-inbox.error.log`.

### Asynchronous Postal Architecture & Scalability Review

Hermes Post is explicitly designed as an **asynchronous postal system** (memos and letters exchanged via private iCloud Drive files), not an instant messaging or WhatsApp clone. Background push notifications (APNs) are intentionally out of scope: the user checks their correspondence when convenient, and the agent replies on its own schedule.

However, a comprehensive review of the file-based communication channel reveals specific scalability and concurrency pain points when scaling up (e.g., 50–100+ threads):

#### 1. $O(N)$ Unbounded Full Directory Scanning Every 5 Seconds
- **Current Behavior:** Every 5.0 seconds in `PostInboxView` (and 2.5s in `DispatchThreadDetailView`), `DispatchStore.scanAllThreads()` traverses all folders in both local `Application Support/threads/` and iCloud `Documents/threads/`. For every thread, it reads `meta.json` from flash storage and decodes it via `JSONDecoder`. On macOS, `companion.py` performs a similar disk sweep.
- **Pain Point at 100 Threads:** 200 directory checks, 200 disk reads, and 200 JSON decodes occur every 5 seconds while in the foreground. This causes flash storage churn, unnecessary CPU/battery consumption, and potential UI frame drops.

#### 2. Archived Threads Are NOT Ignored by the Disk Monitor
- **Resolved Behavior:** `DispatchStore.archiveThread(id:)` moves the thread folder from `threads/{id}` to `archive/{id}` in both local `Application Support/` and iCloud `Documents/` using `NSFileCoordinator`. On macOS, `companion.py --archive <id>` mirrors this move.
- **Performance Impact:** Active foreground polling (every 5.0s on iOS) and background daemon sweeps on macOS enumerate strictly `Documents/threads/`. Archived threads in `archive/` are completely isolated from the hot path and loaded on-demand, reducing active sweep complexity to strictly $O(\text{active})$. Any legacy archived folders found in `threads/` are auto-migrated to `archive/` on the fly.

#### 3. No Delete Capability (Unbounded Growth)
- **Resolved Behavior:** `DispatchStore.deleteThread(id:)` permanently removes the thread folder from both local `Application Support/` and iCloud `Documents/` (handling both active `threads/{id}` and archived `archive/{id}`) using `NSFileCoordinator` with `.forDeleting` options to prevent resurrection during directory reconciliation. On macOS, `companion.py --delete-thread <id>` performs mirrored removal.
- **Performance Impact:** Eliminates monotonic disk growth. Deleted threads are immediately purged from in-memory caches, removing flash I/O and JSON parsing overhead entirely.

#### 4. Unused Synchronization Marker (`.sync_marker.json`)
- **Resolved Behavior:** Both `DispatchStore` (iOS) and `companion.py` (macOS) check the modification date and internal `updated_at` timestamp of `.sync_marker.json` (triggering ubiquitous downloads if in a dataless `..sync_marker.json.icloud` state) before initiating full thread scans. If the marker signature matches the last recorded state and no pending or unreadable tasks remain, directory sweeps and JSON decodes are bypassed entirely.
- **Performance Impact:** Routine foreground polling cycles (every 5.0s on iOS) and background daemon sweeps (every 3s on macOS) drop from $O(N)$ flash directory traversals to an instantaneous $O(1)$ stat check when idle, completely eliminating disk I/O churn and unnecessary CPU/battery consumption across unchanged thread stores.

#### 5. iCloud Evicted Placeholders (`.meta.json.icloud`) Causing UI Jitter
- **Resolved Behavior:** Both `DispatchStore` (iOS) and `companion.py` (macOS) detect dataless `.meta.json.icloud` placeholders and in-flight CloudDocs downloads, triggering background retrieval via `startDownloadingUbiquitousItem` while seamlessly falling back to in-memory cached thread and message representations.
- **Performance Impact:** Eliminates UI flicker, message drops, and disappearing threads during device storage pressure or background CloudDocs resynchronization. The inbox and correspondence views remain completely stable while dataless files materialize asynchronously in the background.

#### 6. Uncoordinated Concurrent File Reads
- **Resolved Behavior:** `DispatchStore.scanDirectory()`, `readMessagesFromDisk()`, sync marker evaluations, and profile lookups coordinate reading ubiquitous items via `NSFileCoordinator` with `.withoutChanges` options (`coordinatedReadData`). Coordinated reads synchronize with `bird` and macOS atomic writes, falling back gracefully to direct reads and in-memory caches if transient errors occur.
- **Performance Impact:** Completely prevents race conditions, partial reads, and transient JSON decode errors caused by concurrent disk synchronization. Thread metadata and incoming letters are always read in an atomically consistent state without cycle-skipping or UI glitches.

#### 7. Message Sequence Number Collisions
- **Resolved Behavior:** Strict turn-based state validation (`status == .replied` required before user reply; `status == .pendingAgent` or `status == .failed` required before agent reply) and optimistic concurrency verification against disk metadata eliminate concurrent turn collisions. Sequence prefix numbers are computed monotonically as `max(messageCount, highestDiskSequence) + 1` across both iOS and macOS, preventing prefix collisions even if out-of-order writes occur.
- **Performance Impact:** Eliminates sequence numbering conflicts, write contention, and non-deterministic chronological letter ordering. The postal communication channel maintains strictly alternating, sequential correspondence between the user and agent across both iCloud and local storage.

---

### Actionable Roadmap: Postal Channel Optimization Tasks

The following tasks address the identified scalability and concurrency bottlenecks:

- [x] **Task 1: Gate Directory Scans with `.sync_marker.json`**
  - Read `.sync_marker.json` modification date / timestamp before initiating `scanAllThreads()` or `companion.py` sweeps.
  - If the marker has not changed since the last known sync, skip the $O(N)$ directory traversal and JSON decoding entirely.
  - Maintain an in-memory dictionary cache of parsed threads keyed by `thread_id` and file `modificationDate`.

- [x] **Task 2: Segregate Archived Threads into `Documents/archive/`**
  - When a thread is archived, move its folder from `Documents/threads/{id}` to `Documents/archive/{id}` (and in local `Application Support`).
  - Active scanning loops on both iOS and macOS should only ever enumerate `Documents/threads/`.
  - Keeps active polling at $O(\text{active})$ instead of $O(\text{total})$, isolating historical threads from the fast path.

- [x] **Task 3: Implement Coordinated Thread Deletion (`deleteThread`)**
  - Add `DispatchStore.deleteThread(id:)` that coordinates atomic directory removal across both `localThreadsDirectory` and `iCloudThreadsDirectory` via `NSFileCoordinator`.
  - Add swipe-to-delete in `PostInboxView` and a destructive Delete button in `DispatchThreadDetailView`.
  - Add `--delete-thread <id>` in `companion.py` for CLI cleanup.

- [x] **Task 4: Graceful Cache Fallback for iCloud Placeholders (`.icloud`)**
  - When `meta.json` is in `.meta.json.icloud` state, retain the previously cached in-memory thread representation while triggering `startDownloadingUbiquitousItem`.
  - Prevents threads from vanishing and flickering in the UI during CloudDocs sync.

- [x] **Task 5: Coordinated Reads with `NSFileCoordinator`**
  - Wrap read operations in `DispatchStore` (`scanDirectory`, `readMessagesFromDisk`, sync marker, and profile loaders) with `NSFileCoordinator` using `.withoutChanges` option to prevent reading half-written files.

- [x] **Task 6: Concurrency Guards & Sequence Collisions**
  - Add optimistic concurrency check or turn-based status validation (`status == .replied` required before user reply, `status == .pendingAgent` required before agent reply) and monotonic sequence index calculation to eliminate sequence collisions.

## Repository

```text
hermes-companion/
├── skills/hermes-companion/     # the Hermes skill (SKILL.md, reader, tests)
│   ├── SKILL.md
│   ├── references/files.md
│   └── scripts/companion.py
├── HermesCompanion/             # SwiftUI app
├── server/                      # MCP server and integration tests
├── assets/                      # wordmark artwork and device captures
├── website/                     # Marketing, Support & Privacy web pages
├── project.yml                  # XcodeGen spec
├── AGENT.md                     # contributor and agent guide
└── README.md
```

Regenerate the Xcode project after adding or removing source files:

```bash
xcodegen generate
```

Simulator build, no signing:

```bash
xcodebuild -project HermesCompanion.xcodeproj -scheme HermesCompanion \
  -sdk iphonesimulator -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build
```

Tests:

```bash
python3 skills/hermes-companion/scripts/test_companion.py
python3 server/test_integration.py
```

The MCP server in `server/mcp_server.py` exposes the same files as tools (`get_user_location`, `get_user_health`, `get_user_physical_context`, place list and add). The skill does not require it. Point Hermes at the script and you are done.

## License

[MIT](LICENSE)
