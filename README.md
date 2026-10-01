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

The phone is in a pocket, often on cellular, often with the app swiped away. Nothing on the internet can open a connection to it. Hermes Companion lets iOS wake the app, writes two JSON files into the app's private iCloud container, and lets the Hermes agent on your Mac read the copies macOS has already synced.

```
iPhone  →  iCloud Drive  →  Mac disk  →  Hermes skill
                latest_location.json
                latest_health.json
```

No account with us. No analytics. No open port. The files stay in your Apple ID.

<p align="center">
  <img src="assets/lilith-black.png" alt="" width="720">
</p>

## What the agent can say

| It knows | Because |
| --- | --- |
| You are still at Home | The location file is rewritten only when a move is accepted. Hours at the same place means you are still there. |
| You are walking, not driving | CoreMotion reports `stationary`, `walking`, `running`, `cycling`, or `automotive` on its own clock. |
| You did not just arrive | A new file means the persist gate accepted a displacement. It does not mean you got home. |
| How you slept and trained | HealthKit sleep is the union of Deep, REM, and Core, so Watch and iPhone samples are not added twice. |

Indoor drift of about 10 m while you are still does not rewrite the file. Fresh walking, running, cycling, or driving is stored at 30 m. A fresh stationary reading is stored only past 150 m, or when GPS speed is above 1 m/s and the 30 m filter is also cleared.

## Install the skill

The skill is `skills/hermes-companion` in this repository. One skill covers place and health.

```bash
hermes skills install danielmain/hermes-companion/skills/hermes-companion
```

Or keep the repo as a tap and install from it:

```bash
hermes skills tap add danielmain/hermes-companion
hermes skills search hermes-companion
```

Then ask where you are, how you slept, or whether you are still at the gym. The agent runs:

```bash
python3 ${HERMES_SKILL_DIR}/scripts/companion.py
python3 ${HERMES_SKILL_DIR}/scripts/companion.py --health
python3 ${HERMES_SKILL_DIR}/scripts/companion.py --context
```

Name the places you care about once. After that, coordinates stay off-screen and the reply says Home, Work, or the gym.

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

1. Open `hermes-companion-ios.xcworkspace` in Xcode.
2. Select your team and run on your iPhone.
3. Allow Location, then upgrade it to **Always** from the in-app banner. Background wakes do not run on While Using.
4. Allow Motion & Fitness and Apple Health.
5. Use the same Apple ID on the phone and the Mac, with iCloud Drive on.

The app keeps working after you leave it, and after iOS relaunches it, through three wake paths plus normal GPS while you are moving:

- Significant location changes, about a cell-tower step, which relaunch a terminated app.
- A stationary geofence (default 100 m) that fires when you leave.
- Visit monitoring for arrivals and departures.
- Standard GPS while the app is allowed to update in the background.

Confirm the Mac can see a fix:

```bash
python3 skills/hermes-companion/scripts/companion.py
```

`source:` should be a file under `~/Library/Mobile Documents/iCloud~com~hermes~HermesCompanion/Documents/`.

Timestamps in the JSON are UTC (`2026-10-01T09:53:05Z`). The script compares them to UTC now, so the age is right in any timezone. A growing age while you stay put is the design: the timestamp is the last accepted move, not the last GPS tick.

## Repository

```text
hermes-companion/
├── skills/hermes-companion/     # the Hermes skill (SKILL.md, reader, tests)
│   ├── SKILL.md
│   ├── references/files.md
│   └── scripts/companion.py
├── HermesCompanion/             # SwiftUI app
├── server/                      # MCP server and integration tests
├── assets/                      # wordmark artwork
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
