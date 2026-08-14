# Changelog

All notable changes to Turtle King are recorded here. Milestone-by-milestone
detail lives in the README; this file is the release-level summary.

## [Unreleased] — Relay deployment tooling

### Added

- **`GET /health` liveness endpoint** on the relay — returns a static
  `{"status":"ok"}` and never exposes join codes, sessions, players, or
  game data (regression-tested).
- **Heartbeat host-loss detection** on the relay — every connection is
  pinged and silent ones are dropped, so a dead host is detected and its
  session torn down even when its WebSocket close frame never reaches the
  relay (app killed, network drop, or a proxy that swallows close frames).
  Fixes host-loss handling behind internet proxies/CDNs; ping/pong frames
  carry no data.
- **Render `PORT` support** in the relay process — honors the platform-
  standard `PORT` environment variable when `RELAY_PORT` is absent
  (precedence: `--port` > `RELAY_PORT` > `PORT` > 8787).
- **Production `Dockerfile`** — multi-stage build (Dart SDK stage compiles
  the relay to an AOT executable; minimal glibc runtime image, unprivileged
  user, PORT-driven).
- **Render deployment guide** in
  `docs/multiplayer/m18-relay-deployment.md` §3.3 (service config, health
  check, `wss://<service-name>.onrender.com` endpoint, smoke test).

## [1.2.0] — Multiplayer release (M18)

Device-to-device multiplayer, release-ready.

### Added

- **Host-authoritative multiplayer** on separate physical devices: the host
  owns the authoritative `GameState`; clients send action requests and render
  only the sanitized public state.
- **RemoteDriver gameplay** — clients play through the same five-action
  surface as pass-and-play (reveal, pass, hold out, YAMADA, next round),
  with host validation and broadcast state updates.
- **Two interchangeable transports** behind one interface:
  - **LAN** (`dart:io` TCP + in-repo UDP multicast beacon discovery,
    manual host-IP fallback), and
  - **Internet relay** (dumb WebSocket relay) for mixed networks —
    Wi-Fi to Wi-Fi, Wi-Fi to mobile data, and mobile to mobile.
- **Reconnection/resync** — identity-preserving reconnect with authoritative
  resync snapshots; **host-loss handling** ends the session cleanly for all
  clients.
- **6-digit join codes** (ambiguity-free digits, `483 729` display) and
  **QR-code joining** (v2 relay payload via `qr_flutter`/`mobile_scanner`).
- **Relay deployment tooling** — embeddable `RelayServer`, standalone runner
  (`tool/relay_server_main.dart`), graceful-shutdown process wrapper,
  deployment + two-phone QA documentation, and an independent smoke test.
- **Privacy-preserving state views** — `PublicStateView` (no card data) and
  `PrivateStateView` (exactly one rule-authorized card to one recipient);
  the relay never parses or logs game payloads or join codes.
- **Version display** — the app version (from `pubspec.yaml`, read through
  the platform package metadata, never hardcoded) is shown as `v1.2.0` on
  the Home screen and in Settings → About.
- **"For Nerds" advanced section** — the join lobby's advanced LAN/manual-IP
  options now live under a collapsed **For Nerds** section ("Advanced
  options for curious turtles.") instead of the developer-facing
  "Developer options" label; QR and code joining remain the primary paths.

### Notes

- Internet/mixed-network play requires a **deployed public relay** reached
  via `--dart-define=RELAY_URL=...` (see
  `docs/multiplayer/m18-relay-deployment.md`).
- Physical two-device verification against a deployed public relay is the
  one outstanding item; see `docs/multiplayer/m18-mixed-network-qa.md`.

## [0.1.0] — Pass-and-play game (M01-M17)

The complete pass-and-play game shipped before multiplayer:

- Authoritative Turtle King rules: two cards / one visible, the pouring cup,
  YAMADA = admit defeat, hold-out reveal, cup escalation, six-drink
  elimination, Turtle King.
- Milestones 01-17: project foundation, player setup, card system, pass-and-play
  flow, rule documentation, history/replay, branding, card-table UI,
  personalization & themes, save/resume, sound/haptics, small-screen audit.
- All multiplayer work (Phase 18 / M18) is additive — pass-and-play remains
  complete and unchanged.
