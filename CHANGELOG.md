# Changelog

All notable changes to Turtle King are recorded here. Milestone-by-milestone
detail lives in the README; this file is the release-level summary.

## [1.3.0] — 2026-08-19 — M19 Bluetooth multiplayer

### Fixed

- **Bluetooth host startup on real Android devices.** Two physical-device
  defects in the BLE plugin interaction are fixed:
  - The permission handshake no longer hangs on "Starting…" forever: the
    plugin's `authorize()` can silently never complete (its result callback
    is not delivered when permissions are already granted, and its adapter
    state is only refreshed at construction/app-resume — never after
    `authorize()`). `ensureAuthorized()` now skips the request when the
    state already knows the permissions are granted, bounds each request
    with a timeout, and races the callback against the post-prompt state
    refresh so a lost callback cannot leave the lobby hanging.
  - The host no longer **renames the user's phone** or hangs on repeat
    starts: the Android plugin advertises a name by renaming the device
    (`BluetoothAdapter.setName`), and once the name is unchanged the
    `ACTION_LOCAL_NAME_CHANGED` broadcast never fires, so the second host
    start hung forever. The advertisement now carries the service UUID
    only (joiners match on the UUID and show the fallback game name), and
    advertising is bounded by a timeout so any platform hang surfaces as a
    friendly error instead of an infinite spinner.
  - **"Search for nearby games" found nothing on real devices.**
    `BleSessionDiscovery` subscribes to the adapter's `discovered` stream
    *before* `startScan()` is called, but `PluginBleAdapter.discovered`
    returned an empty stream until the scan started — so the listener was
    bound to a dead stream and every scanned host was silently dropped
    (the in-memory test fake was lazy, which is why unit tests never
    caught it). The real adapter's `discovered` getter is now lazy too,
    matching the fake, so hosts actually appear in the nearby list.
  - **Host game start crashed on real devices.** `HostSession.events` was a
    single-subscription stream, but two consumers co-listen — the host
    lobby (roster/status) and `HostRemoteController` while the host plays
    its own game — so the second `listen` threw "Stream has already been
    listened to" and the host's game never started after a player joined.
    The stream is now broadcast (the client session was already), so
    hosting a game over Bluetooth (and LAN/relay) works end to end.
  - **Discovery hardening** — `BleSessionDiscovery` now verifies a scanned
    peer actually advertises the Turtle King service UUID (unrelated BLE
    advertisers are ignored), deduplicates repeated advertisements from
    the same device, falls back to a friendly name for blank
    advertisements, and a fresh search after stopping restarts scanning
    correctly.
  - **Mid-game Bluetooth reconnect on real devices.** When a joiner's
    link dropped mid-game, the host's peripheral could miss the
    `BleHostDisconnected` event, leaving a stale connection in the
    server's peer map. A reconnecting client (whose GATT reconnect
    succeeded) was then silently skipped — the rejoin's `JOIN_REQUEST`
    never reached the session layer and the joiner timed out with
    "Connection failed." `BleTransportServer` now **replaces** a stale
    peer entry on re-admission (tearing down the old connection so the
    session frees the player seat) and guards the stale connection's
    close so it can't `dropPeer` the fresh GATT link that shares the
    same peer id. The joiner reclaims its original identity with no
    duplicate roster entry.
  - **Remote gameplay screens froze after the first action on real
    devices.** The game advanced on both phones (the host applied the
    action and broadcast the new state, which the client received), but
    neither screen re-rendered — the client's first "Reveal" and the
    host's own reveal both looked like they did nothing. Root cause:
    `RemoteGameScreen` rebuilds only on `RemoteGameEvent`, but
    `RemoteDriver` updated its internal view on `stateUpdated` /
    `privateUpdated` without emitting one, and `HostRemoteController`
    emitted nothing after a successful action either. Both now notify
    the UI when the view changes, so accepted actions immediately
    re-render on both devices (regression tests pin the contract).

### Added

- **Bluetooth Low Energy multiplayer transport** (`lib/multiplayer/ble/`) —
  a third transport behind the existing `MultiplayerTransport` interface
  (alongside LAN/TCP and the internet relay). The host publishes a Turtle
  King GATT service and advertises the service UUID (no game name — the
  Android plugin renames the device to advertise a name, which hangs
  repeat hosts, so joiners match on the UUID and show the fallback name);
  clients scan for nearby hosts, connect as GATT centrals, and play
  through the unchanged session/protocol layer — host-authoritative
  `GameState`, `PublicStateView`/`PrivateStateView` privacy, reconnection,
  host-loss. No internet and no Wi-Fi required; the phones just need to be
  nearby.
- **Chunked BLE framing layer** (`ble_framing.dart`) — fits the existing
  canonical-JSON protocol messages into MTU-sized GATT notifications/writes
  with a versioned chunk header, bounded buffering, and strict
  malformed-frame rejection (protocol-violating peers are dropped).
- **Host Game → Bluetooth mode** and a **Nearby (Bluetooth)** join path —
  permission-denied, adapter-off, unsupported, no-peers, and
  connect-failure states surface as friendly messages; no raw Bluetooth
  terminology is shown to normal users.
- **Rejoin over Bluetooth** — `RemoteDriver` reconnects through the same
  BLE transport (peer identifier addressing, port 0) instead of assuming a
  LAN address/port.
- **Android/iOS permissions** — `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` /
  `BLUETOOTH_ADVERTISE` (Android 12+), legacy `BLUETOOTH`/`BLUETOOTH_ADMIN`
  + location below Android 12, an optional (`required="false"`)
  `android.hardware.bluetooth_le` feature, and
  `NSBluetoothAlwaysUsageDescription` on iOS.

### Dependency

- `bluetooth_low_energy ^6.2.1` (MIT) — supports **both** central and
  peripheral roles on Android and iOS (the only maintained Flutter BLE
  package that does), so the host and client share one transport. The
  session layer stays transport-agnostic behind the `BleAdapter` seam;
  only `plugin_ble_adapter.dart` imports the package.

### Notes

- Bluetooth multiplayer is covered by in-process tests with an in-memory
  simulated BLE network (framing, join, gameplay, private-card isolation,
  host loss, reconnect, malformed frames) on top of the existing suite.
  **Physical two-device Bluetooth testing has not yet been performed** —
  see `docs/multiplayer/m19-bluetooth-qa.md`.

## [1.2.1] — Multiplayer relay reliability

Post-v1.2.0 production fixes for the deployed internet relay.

### Fixed

- **Heartbeat host-loss detection** on the relay — every connection is
  pinged (2s interval) and silent ones are dropped (10s timeout), so a dead
  host is detected and its session torn down even when its WebSocket close
  frame never reaches the relay (app killed, network drop, or a proxy/CDN
  that swallows close frames). Fixes host-loss handling behind internet
  proxies; clients answer automatically, and the ping/pong frames carry no
  data. Verified 7/7 against the live public relay
  (`wss://turtleking.onrender.com`), including host-loss.
- **Slow/cold relay joins** — the relay join timeout is raised from 8s to
  30s per attempt with **one controlled retry** for transient failures, so
  a Render free-tier relay that is mid-wake (30–60s cold start after idle)
  is given time to boot instead of failing after 8s. Permanent failures
  (invalid code, unavailable/expired session, protocol rejection, host
  rejection) are never retried. While waiting, the join lobby shows
  `Connecting…` and then `Waking the multiplayer relay…` after a delay —
  no networking/developer terminology.

### Added

- **`GET /health` liveness endpoint** on the relay — returns a static
  `{"status":"ok"}` and never exposes join codes, sessions, players, or
  game data (regression-tested).
- **Render `PORT` support** in the relay process — honors the platform-
  standard `PORT` environment variable when `RELAY_PORT` is absent
  (precedence: `--port` > `RELAY_PORT` > `PORT` > 8787).
- **Production `Dockerfile`** — multi-stage build (Dart SDK stage compiles
  the relay to an AOT executable; minimal glibc runtime image, unprivileged
  user, PORT-driven).
- **Render deployment guide** in
  `docs/multiplayer/m18-relay-deployment.md` §3.3 (service config, health
  check, `wss://<service-name>.onrender.com` endpoint, smoke test).

### Notes

- The live public relay is at `wss://turtleking.onrender.com` (health
  `{"status":"ok"}`, smoke test 7/7 including host-loss). Physical
  two-phone mixed-network testing has **not** been performed; see
  `docs/multiplayer/m18-mixed-network-qa.md`.

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
