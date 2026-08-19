# M19 — Bluetooth Multiplayer: Physical-Device QA Checklist

**Status: NOT YET EXECUTED.** The Bluetooth implementation is covered by
in-process tests with an in-memory simulated BLE network, but **no two
physical devices have been connected over Bluetooth yet**. Do not mark any
row Passed until it has actually been performed on hardware.

## Prerequisites

- Two Android devices (Android 6.0+ / API 23+, or 8.0+ / API 26+ for the
  modern permission model) — one becomes the host, one the client.
- Build the app with the normal debug or release command (no relay needed
  for Bluetooth — this path is internet-free):

```sh
flutter build apk --debug
# or
flutter build apk --release
```

- Install on both phones. Enable Bluetooth (and Location / Nearby-devices
  permission on Android 11 and below) on both.
- Keep the phones within a few meters during discovery and connection.

## Flow to exercise

1. Phone A: Multiplayer → Host Game → **Bluetooth**.
2. Phone A: allow the Bluetooth permission prompt; confirm "Bluetooth is
   off" style guidance does not appear (it should be on).
3. Phone A: confirm the roster lobby shows "Nearby players can join…".
4. Phone B: Multiplayer → Join Game → **Nearby (Bluetooth)** → allow the
   permission prompt → confirm a host appears in the list within a few
   seconds. Note: hosts advertise the service UUID only (Android's plugin
   renames the device to advertise a custom name, which hangs repeat
   hosts), so the entry shows the fallback game name "Turtle King game"
   — the real game name appears in the roster after joining.
5. Phone B: tap **Join** → confirm "Connecting…" progress → confirm the
   player appears in Phone A's roster.
6. Phone A: Start Game → both phones enter the game; the client renders
   only its public state + its own private card.

## Acceptance matrix

| # | Test | Expected | Result |
| --- | --- | --- | --- |
| 1 | Host → Bluetooth with Bluetooth off | Friendly "Bluetooth is off" message, no crash | ☐ Not run |
| 2 | Host → Bluetooth with permission denied | Friendly permission message pointing at Settings | ☐ Not run |
| 3 | Host → Bluetooth, then client scans | Host appears in Nearby list | ☐ Not run |
| 4 | Client joins a discovered host | Player appears in host roster | ☐ Not run |
| 5 | Duplicate join taps | Only one join attempt (roster gains one player) | ☐ Not run |
| 6 | Start game from host | Client receives state and enters gameplay | ☐ Not run |
| 7 | Client plays a turn | Host validates and broadcasts; both screens update | ☐ Not run |
| 8 | Private card isolation | Client only ever sees its own visible card, never others' hands or the deck | ☐ Not run |
| 9 | Host walks out of range / closes app | Client shows host-loss/session-ended handling within ~15s (heartbeat) | ☐ Not run |
| 10 | Client walks out of range | Host roster updates; client shows reconnecting state | ☐ Not run |
| 11 | Client comes back in range | Reconnect over BLE (peer id) → resync → back in lobby/game | ☐ Not run |
| 12 | Host ends the session | Both phones return to multiplayer menu cleanly | ☐ Not run |
| 13 | Malformed nearby device | A non-Turtle King BLE device is ignored; no crash | ☐ Not run |
| 14 | Second client joins (3 phones) | Both clients appear; gameplay works for both | ☐ Not run |
| 15 | Phone A hosts via relay afterwards | Relay path still works (regression, internet needed) | ☐ Not run |

## Notes

- Rows 9–10 may take up to ~15 seconds to surface: iOS exposes no
  peripheral-side disconnect event, so silent-peer reaping relies on the
  session heartbeat (5s interval / 15s timeout), exactly as on the relay.
- Bluetooth multiplayer requires no internet and no Wi-Fi — verify at least
  one row (e.g. #4 or #7) with **both phones in airplane mode** (Bluetooth
  still enabled) to prove the path is offline-capable.
- Physical-device results are reported separately from the in-process test
  suite; automated tests passing does **not** imply hardware verification.
