# Sijak

Digital scoring system for Taekwondo (PSS-style), replacing manual stick scoring. Runs entirely over local WiFi — no server, no internet required.

## How it works

- **3 iPhones (Judges)** — each gets a red/blue panel with point buttons (1/2/3/5). A point only counts once **2 of 3 judges** press the same button within ~1.2 seconds.
- **1 device (Monitor)** — hosts the match, tallies judge votes, runs the round timer, and is the single source of truth for the score. Can run as:
  - A **macOS app**, or
  - One of the iPhones itself, via **"Host a Match"** — this also serves a **live, read-only web scoreboard** (shown as a link on screen) that anyone on the same WiFi can open in any browser, no app install needed.
- Best-of-3 rounds, with configurable **Gap Point**, **Ceiling Point**, and round timer, plus manual gam-jeom (penalty) and point-correction controls for the operator.

## Project structure

Two Xcode targets sharing the same source tree:

| Target | Platform | Entry point |
|---|---|---|
| `DSSHHH` | iOS | `DSSHHHApp.swift` → `RoleSelectionView` (choose Judge or Host) |
| `DSSHHH-Mac` | macOS | `DSSHHHMacApp.swift` → `MonitorHostView` |

```
DSSHHH/
├── Models/RoomModels.swift          # shared data model + network messages
├── ViewModels/MultipeerManager.swift # MultipeerConnectivity + match logic (shared)
├── Services/
│   ├── MatchLogService.swift        # match history logging/export (shared)
│   └── MonitorWebServer.swift       # embedded HTTP/SSE server for the web scoreboard (shared)
├── Views/
│   ├── Judge/                       # iOS-only: judge join + scoring screens
│   ├── Monitor/                     # shared: room code, match setup, scoring/host screens
│   └── Shared/                      # role picker, QR scanner (iOS-only)
```

## Building it yourself

There's no TestFlight/App Store build yet, so to try it you'll need Xcode and your own free or paid Apple Developer account:

1. Clone the repo and open `DSSHHH.xcodeproj` in Xcode.
2. Pick a scheme:
   - **`DSSHHH`** — build to an iPhone (needs a physical device for MultipeerConnectivity + camera QR scanning; the simulator won't discover peers).
   - **`DSSHHH-Mac`** — build to run on your Mac.
3. In each target's Signing & Capabilities tab, set your own Team so Xcode can sign the build.
4. Run the Monitor (Mac app, or "Host a Match" on one iPhone) first, then run the Judge app on the other iPhones and join using the room code or QR shown on the Monitor.

All devices must be on the same WiFi network. On first connect you'll be prompted for local network permission — allow it, or discovery won't work.
