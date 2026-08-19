# M18 — Device-to-Device Multiplayer: Architecture & Transport Discovery

> This document is the design record for Phase 18 (multiplayer between
> separate physical devices). It began as the M18.1 architecture/discovery
> proposal and now records the implemented milestone progression through
> **M18.6** (§7.x, §7.6). The pass-and-play experience remains complete and
> unchanged.

- Status: **implemented through M18.6** (this header reflects the original M18.1 proposal; milestone records are appended in §7.x)
- App: Turtle King — pass-and-play card game (Flutter 3.44.8, Dart 3.12.2, minSdk 24)
- Branch: `feature/milestone-18-offline-multiplayer`
- Release: tagged as **v1.2.0** (multiplayer release)

---

## 1. Current architecture findings

Inspected (M18.1):

| Area | Files | Findings |
| --- | --- | --- |
| Rules engine | `lib/game_state.dart` | Single authoritative `GameState` class implements every rule. All gameplay actions are synchronous, validated, and atomic (rejected actions throw `YamadaRoundException` with no mutation). Public API used by the UI: `revealCurrentPlayer()`, `passToNextPlayer()`, `holdOut(player)`, `callYamada(player)`, `startNextRound()`. Exposes a large read surface (`currentPlayer`, `pouringStarted`, `roundNumber`, `cupSize`, `drinksOf`, `calledYamadaThisRound`, `smallestHands`, `revealedPlayers`, `eliminationHistory`, `finalResult`, `events`, …). |
| Player model | `lib/player.dart`, `lib/player_colors.dart`, `lib/player_setup_screen.dart` | `Player(id, name, color)` value-type; **setup order is play order**; 2–10 players; colors auto-assigned. |
| Save/resume | `lib/game_save.dart` | Versioned JSON codec (`GameSaveCodec`, schema v1) round-trips **everything**, including all hands and the remaining deck order, via `GameState.restore`. Local-only (SharedPreferences). |
| History/replay | `lib/game_state.dart` (events), `lib/game_history_screen.dart`, `lib/round_history_screen.dart` | `GameEvent` log is documented and tested to be **card-identity-free**; screens are read-only. |
| Privacy contract | throughout | Only `visibleCardOf(player)` may ever be shown; the second card is hidden even from its owner until the group reveal. Events, history, save summaries, and audio never carry card identities (regression-tested). |
| Audio/haptics | `lib/feedback.dart` | `GameFeedback` seam; `FeedbackEvent` is identity-free; sound/haptic gates independent; playback local and failure-contained. |
| Navigation | `lib/main.dart`, `lib/splash_screen.dart`, `lib/home_screen.dart`, `lib/player_setup_screen.dart`, `lib/game_start_screen.dart` | `Splash → Home → PlayerSetup → GameStartScreen(game)`. `GameStartScreen` is **presentation-only**: all logic lives in `GameState`; the screen calls state methods directly from its action handlers. |
| Dependencies | `pubspec.yaml` | Runtime: `shared_preferences ^2.5.3`, `audioplayers ^6.8.1`, `qr_flutter ^4.1.0` (QR rendering), `mobile_scanner ^7.4.0` (QR scanning). Dev: `audioplayers_platform_interface`, `crypto`, `flutter_lints`. No networking package — `dart:io` TCP/UDP/WebSockets only. |
| Android config | `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts` | `minSdk = flutter.minSdkVersion` (= **24**, Flutter default), compile/target = Flutter defaults. Manifest declares `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE` (M18.3) and `CAMERA` (M18.5). |
| Tests | `test/` (+ `test/multiplayer/`) | 599 tests; rules/state privacy and determinism heavily covered; widget tests drive the full game flow; `small_screen_test.dart` plays a full game at 320×568; the multiplayer suite covers codec, LAN TCP loopback, relay in-process loopback over real WebSockets, privacy, reconnect, host loss, and relay logging. |

### 1.1 The multiplayer integration boundary

The clean seam is **between the presentation layer and `GameState`**:

```
UI (GameStartScreen + lobby)
        │  action calls
        ▼
GameDriver  ◄── NEW abstraction (M18.2+)
        │  ├─ LocalDriver      → wraps a real GameState directly (pass-and-play today)
        │  └─ RemoteDriver     → sends ACTION_REQUEST over the session, renders broadcast state
        ▼
GameState  (authoritative rules engine — UNCHANGED, host-only in multiplayer)
```

- `GameState` remains the single rules engine. Network code transports
  commands and sanitized state; it **never duplicates rules**.
- `GameStartScreen`'s five action handlers (`_reveal`, `_pass`, `_yamada`,
  `_holdOut`, `_startNextRound`) are the exact interception points: they call
  state methods directly today; in multiplayer they route through the driver.
- The host owns the real `GameState`. Clients render a read-only
  `RemoteGameView` (public getters) plus their own private card.
- `GameSaveCodec` is **not** the network codec — it serializes hands and the
  deck, which must never leave the host.

---

## 2. Multiplayer goals

1. 2–10 people play the same Turtle King game from **separate physical devices**, offline (no internet).
2. Each player sees **only what the rules allow**: their own one visible card, then the authorized group reveal.
3. The host's `GameState` remains the single source of truth; clients never compute game rules.
4. Connection setup is simple enough for a party game (discover → join → play).
5. Reconnection after a dropped link restores the player to the current public state.
6. The existing pass-and-play flow keeps working unchanged (LocalDriver).

## 3. Non-goals (M18 scope)

- **No** changes to `GameState`, deck/card rules, save/resume, history/replay, settings, audio, or pass-and-play.
- ~~**No** internet play / matchmaking servers / accounts.~~ **Revised by M18.6:** internet play via a minimal dumb WebSocket relay is now supported (no matchmaking, no accounts); the relay adds no auth and stores no game data.
- **No** host migration in v1: if the host leaves, the session ends explicitly (see §14).
- **No** encryption/TLS in v1 (local, trusted-network play; documented in §11/§17).
- **No** gameplay-rule duplication anywhere on the client.
- **No** AI/solo mode.

## 4. Recommended topology

**Host-authoritative star:**

```
                 ┌─────────────┐
                 │  HOST phone │  owns GameState, session, roster
                 │  (server)   │  LAN: TCP ServerSocket + beacon advertises
                 │             │  Relay: one outbound WebSocket (M18.6)
                 └──────┬──────┘
          ┌─────────────┼─────────────┐
          ▼             ▼             ▼
      Client 2       Client 3  ...  Client 10
      (LAN: TCP socket per client; relay: virtual connection per member)
```

- **Host** = the device that creates the session (mirrors the person who starts the game today). Runs the real `GameState`.
- **Clients** = every other device; each maps 1:1 to one roster player, in join order (which is play order, matching today's "order added = order played").
- All game actions are **requested by the acting client** and **validated + applied by the host**; the host then broadcasts the new public state.
- 2–10 simultaneous TCP connections is trivial for a server socket and has no practical Android limit (unlike BLE, see §5).

## 5. Transport comparison

> **M19 update:** this section records the **M18** decision. M19 later
> adopted Bluetooth Low Energy as a *third* local transport using
> `bluetooth_low_energy` (which supports both central and peripheral roles,
> unlike the central-only `flutter_blue_plus` evaluated here) — see
> `docs/multiplayer/m19-bluetooth-architecture.md`. The M18 conclusion —
> BLE is not the *primary internet* transport — is unchanged.

### 5.1 Bluetooth (BLE) — rejected as primary

| Criterion | Finding |
| --- | --- |
| Flutter support | `flutter_blue_plus` 2.3.12 (active, published frequently) — but **BLE Central role only**; Bluetooth Classic unsupported. Peripheral role needs a separate package (`FlutterBlePeripheral`/`bluetooth_low_energy`). |
| Android support | Central-to-N-peripherals works, but practical concurrent-connection limits (~5–7, device-dependent) and stability degrade with 9 clients. |
| Discovery | BLE scanning + advertisement; usable but noisier than mDNS; needs service UUID filters. |
| Pairing UX | Requires Bluetooth permissions and often OS-level pairing flows; friction for a party game. |
| Permissions | `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` (API 31+), legacy `BLUETOOTH`/`BLUETOOTH_ADMIN` below; runtime permission prompts. |
| Latency | Low (tens of ms per small message) but connection management dominates complexity. |
| Reconnection | Supported (`autoConnect`), but services must be re-discovered after each drop; flaky in practice. |
| **Licensing** | ⚠️ `flutter_blue_plus` moved to a **source-available "FlutterBluePlus License": free for personal/nonprofit, commercial license required for for-profit use.** Material for a commercial app. |
| Testing | Largely hardware-dependent; no clean in-process test story. |

### 5.2 Wi-Fi Direct — rejected

| Criterion | Finding |
| --- | --- |
| Flutter support | Plugins poorly maintained (`wifi_direct_plugin` rated **Poor** maintenance on fluttergems; `flutter_p2p_connection`, `nearby_service` are small/niche). |
| Android support | Android P2P API (WifiP2pManager) is functional but **group formation disconnects devices from their normal Wi-Fi** (no internet while playing), fragile with many peers. |
| Permissions | `NEARBY_WIFI_DEVICES` (API 33+), legacy `ACCESS_WIFI_STATE`/`CHANGE_WIFI_STATE`/`ACCESS_FINE_LOCATION`. |
| UX | Devices leave their Wi-Fi network; discovery + group negotiation is slow and flaky. |

### 5.3 Local Wi-Fi (LAN TCP + mDNS) — historical M18.1 recommendation

> As delivered (M18.3/M18.6), LAN is the developer/debug fallback: discovery
> is the in-repo UDP beacon protocol (not `multicast_dns`, which is
> query-only — §7.2) and the production transport is the WebSocket relay (§6,
> §7.4). The table below is the original M18.1 research.

| Criterion | Finding |
| --- | --- |
| Flutter support | **Transport needs no package at all**: `dart:io` `ServerSocket`/`Socket` is in the SDK. Discovery via `multicast_dns ^0.3.3+1` — **published by `flutter.dev`**, BSD-3-Clause, pure Dart, 4.8M downloads, actively updated (2 months ago), zero native code. |
| Android support | Plain TCP sockets + mDNS multicast; reliable on all Android ≥ 7 (minSdk 24). |
| Discovery | mDNS service advertisement/query (`_turtleking._tcp`); manual IP entry fallback (§17). |
| Pairing | None — join is in-app (name + host picks a session). Best party UX. |
| Permissions | `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE` (normal permission, auto-granted). No runtime prompts. |
| Latency | Sub-millisecond to a few ms on the same Wi-Fi. |
| Reconnection | Trivial: reconnect TCP, request a resync snapshot (§13). |
| 2–10 players | No connection-count practical limit for a server socket. |
| Offline | Fully offline — same LAN only, no internet needed. |
| Testing | `dart:io` loopback (`127.0.0.1`) sockets work in plain unit tests — a full host+clients game can run **without hardware**. |
| iOS (later) | `dart:io` + `multicast_dns` work on iOS; requires `NSLocalNetworkUsageDescription` + `NSBonjourServices` in Info.plist. |
| Release | No native plugin to configure; manifest permissions only. |

## 6. Recommended transport

> **Revised by M18.4/M18.6:** the LAN transport below remains the developer/
> debug fallback. The production transport is the **dumb WebSocket relay**
> (§7.4): every device opens one outbound WebSocket to a public relay, so
> any mix of Wi-Fi/mobile-data networks works with no same-Wi-Fi
> requirement. QR + 6-digit code are the primary join mechanisms; LAN
> discovery/manual IP are collapsed developer options.

**Local Wi-Fi (LAN): TCP sockets (`dart:io`) for transport + mDNS (`multicast_dns`) for service discovery.**

Rationale: zero native surface, SDK-only transport, Flutter-team-maintained BSD-licensed discovery, no pairing, no connection-count limits, clean loopback testing, and no license risk. Bluetooth is kept as a documented future alternative only if the product ever needs it (it would not be BLE-with-`flutter_blue_plus` in a commercial app without license review).

## 7. Dependency recommendation

| Package | Version | Role | License | Source |
| --- | --- | --- | --- | --- |
| *(none — `dart:io`)* | SDK | TCP `ServerSocket`/`Socket`, UDP multicast beacons, WebSocket relay transport | BSD (Dart SDK) | dart.dev |

- **Final state: no networking package was added.** The originally-planned
  `multicast_dns` was rejected in M18.3 as **query-only** (it cannot
  advertise a host service, so it cannot satisfy the host side of
  discovery) — see §7.2. Discovery is an in-repo UDP multicast beacon
  protocol (`lib/multiplayer/discovery.dart`), zero dependencies.
- No other networking packages. Specifically **do not** use
  `flutter_blue_plus` (source-available license + BLE-central-only +
  connection limits) or Wi-Fi Direct plugins (maintenance).
- All of the above is compatible with Flutter 3.44.8 / Dart 3.12.2 / minSdk 24.

### 7.1 Dependency & license verification (recorded during M18.2, 2026-08-11)

**`multicast_dns`** — re-verified directly on pub.dev (https://pub.dev/packages/multicast_dns):

- Latest: **0.3.3+1**, published **2 months ago**, publisher **flutter.dev**, **4.8M downloads**.
- License: **BSD-3-Clause**; pure Dart (dependency: only `meta`); zero native code; supports Android, iOS, Linux, macOS, Windows.
- Verdict: unchanged recommendation — safe to add when discovery is implemented.

**`flutter_blue_plus`** — independent verification of the licensing claim by reading the repository's LICENSE.md directly
(https://github.com/chipweinberger/flutter_blue_plus/blob/master/LICENSE.md, **FlutterBluePlus License v1.5, © 2026 Chip Weinberger**):

- The M18.1 claim is **confirmed and is stronger than stated**: this is a custom **source-available** license, not BSD.
- §1.3: *"Use of the Software by any for-profit organization requires a commercial license…"* and §3.3: *"Use of the Software during development, testing, or evaluation by a for-profit organization is considered commercial use and requires a commercial license."*
- §1.4: the package may send a **build-time license telemetry ping** (package name, app name, app version, package version, date).
- §3.1: commercial licenses are **tiered by employee count** (Starter 0–9 … Corporate 250+) with fees set on the vendor's payment portal.
- Verdict: **do not use** in this app without a commercial-license purchase; the LAN/mDNS recommendation stands.

### 7.2 M18.3 transport implementation notes (recorded 2026-08-12)

**M18.3 implements the LAN transport without adding any package.** Verification during M18.3
found a hard blocker in the originally-planned `multicast_dns` package:

- Re-read the package source and API docs (https://pub.dev/documentation/multicast_dns/latest/):
  it is **query-only**. There is no `registerService`/advertisement API anywhere in the
  package — `MDnsClient` can only *look up* `PTR`/`SRV`/`A` records. It cannot advertise a
  host service, so it cannot satisfy the host side of discovery.
- `flutter_nsd` (the other candidate) is likewise **discovery-only**; and the `nsd` package
  that *does* support both registration and discovery has an **undeclared license**
  ("pending") and no way to run its native code in CI.

**Decision (implemented in M18.3):** the app now ships a tiny in-repo UDP multicast beacon
protocol (`lib/multiplayer/discovery.dart`) that satisfies the same `SessionDiscovery`
interface and needs **zero dependencies**:

- Host: `advertise()` periodically broadcasts a canonical-JSON beacon to group
  `239.255.77.77:5354` carrying only `{v, type: BEACON, sessionId, displayName, port}`.
- Client: `discovered` listens on the same group/port, validates every datagram, and emits
  `DiscoveredSession`s; malformed/foreign beacons are ignored (never throws).
- Android: `CHANGE_WIFI_MULTICAST_STATE` + a multicast-lock MethodChannel
  (`lib/multiplayer/platform_multicast.dart`) so phones reliably receive beacons; the lock
  is best-effort and skipped where the channel is unavailable (tests, desktop).
- Manual host-IP join remains the always-available fallback (multicast is blocked on many
  home routers). This matches the M18.1 design (§17) and the interface contract from M18.2.
- The `multicast_dns` package is **not added** and is no longer recommended: it cannot
  advertise, which was its only role. No runtime networking dependency is introduced.

**M18.3 also hardened the TCP transport**: `TcpTransportConnection` now serializes writes
through a per-connection FIFO queue. Two back-to-back unawaited sends (as the host issues
JOIN_ACCEPT then ROSTER_UPDATE) previously overlapped `Socket.flush()` calls, which fails on
some platforms with *"StreamSink is bound to a stream"* and silently dropped the second
frame. The queue guarantees frames are never lost or reordered regardless of caller timing.

### 7.3 M18.5 join UX: QR + 6-digit code (recorded 2026-08-12)

M18.5 keeps the transport/session architecture unchanged and adds a **UX layer only**:

- **Join code** (`lib/multiplayer/join_code.dart`): 6 digits drawn from `2–9` (no `0`/`1`,
  avoiding handwritten ambiguity), `8^6 = 262,144` combinations, displayed grouped as
  `483 729`. The code is a **locator, not a credential**: it is broadcast in the discovery
  beacon (`code` field) and carried in the QR payload, and the host never trusts it — every
  join still goes through the normal `HostSession`/`ClientSession` protocol validation.
  Collisions are handled safely by resolving to the first matching beacon and letting the
  join handshake do the real validation.
- **QR payload** (`lib/multiplayer/join_payload.dart`): versioned canonical JSON
  `{v, t: TKJOIN, sid, host, port, code}` — strictly validated on parse (version, type,
  IPv4, port range, 6-digit code). It contains **only** the connection/session locator:
  no cards, hands, ranks/suits, deck, save data, history, or player identity.
- **Discovery**: beacons now optionally carry the join `code`; `resolveJoinCode()` matches a
  typed code to a session and returns a **typed result** (`JoinCodeResolution`: found /
  notFound / unavailable). It checks the sessions already seen by the lobby first (a valid
  code joins instantly, never waiting for a beacon cycle), then listens on the client's live
  discovery stream for a short explicit window (default 4s), after which a wrong code fails
  fast with "No game found with this code". The discovery stream is a **broadcast** stream:
  the lobby's live "Nearby games" listener and a one-shot code-resolution listener coexist.
  This fixes the real-device bugs where a code entry stuck forever (single-subscription
  stream error) and a wrong code waited out a 12s timeout.
- **Rendering**: `qr_flutter ^4.1.0` (BSD-3-Clause, pure-Dart widget layer over the `qr`
  codec; no native code) draws the host's QR.
- **Scanning**: `mobile_scanner ^7.4.0` (BSD-3-Clause, CameraX/ML Kit on Android, actively
  maintained) powers the client's Scan QR screen; adds the `CAMERA` permission to the
  manifest. The scanner is isolated behind a thin screen + injectable seams so widget tests
  never touch the camera.

  **Known upstream forward-compat warning (observed on a real device build, Flutter
  3.44.8 + AGP 9.0.1):** Flutter's tool prints
  `Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): mobile_scanner`.
  This is a **static** check — the Flutter Gradle plugin regex-matches the plugin's
  `android/build.gradle` for the literal `apply plugin: 'kotlin-android'` line (which
  mobile_scanner keeps, runtime-conditional on built-in Kotlin being disabled), and it only
  runs when the app's AGP major ≥ 9. It is non-fatal today (builds and installs fine) but
  Flutter warns it will become fatal in a future release. Removing the template's
  `android.builtInKotlin=false` flag does **not** silence it (the check is text-based) and
  risks the build. Tracked upstream: mobile_scanner issues #1708/#1721 (closed via the
  conditional-apply workaround; maintainer notes a Flutter-side bug, see #1635). The fix is
  a future mobile_scanner release whose build script drops the KGP line entirely — no
  project-side change is safe to make. Re-check on each `flutter pub upgrade`.
- **Endpoint selection** (M18.5 follow-up): the QR host field is chosen by
  `localLanIpv4Addresses()` — deterministic Wi-Fi/Ethernet-first scoring that excludes
  cellular/VPN/Bluetooth-PAN/USB-tether/loopback interfaces (see
  `lib/multiplayer/net_utils.dart`), replacing the old "first IPv4 from kernel order".
- **Client flow**: Scan QR → parse/validate payload → connect; or Enter code → resolve via
  discovery → connect. Both reuse the existing `ClientSession`/`RemoteDriver` join; manual
  host-IP entry remains only as a collapsed debug fallback.
- **Join reliability (M18.5 fix pass, real-device driven)**: every join failure is contained
  and mapped to a concise user-facing message (invalid code, no game found, game
  unavailable, connection failed/timed out, protocol mismatch, session ended) — raw
  `SocketException`/`TimeoutException`/stack traces never reach the user. A valid QR scan
  shows "Connecting…" immediately; repeated taps cannot start a duplicate join attempt; the
  6-digit code field always starts empty with Android autofill disabled; and the QR scanner
  surfaces camera failures (permission denied / unsupported) as a clear message instead of a
  dead black screen.

### 7.4 Internet relay: removing the same-Wi-Fi requirement (recorded 2026-08-12)

The LAN architecture (§5.3, M18.3) inherently requires local reachability: the host
*is* the server, bound to a private LAN IPv4, discovered by UDP multicast, joined by
**direct** client→host TCP. Private IPs are unreachable across the internet without port
forwarding/NAT tricks, so two phones on different networks could never play.

**Decision:** keep the host-authoritative session/protocol/privacy layers intact and
replace only the transport hop with a **minimal dumb WebSocket relay**. No port
forwarding, no public-IP guessing, no router configuration, no UDP multicast across the
internet — every device opens one **outbound** WebSocket to a reachable relay endpoint,
so any mix of Wi-Fi/mobile-data networks works (Wi-Fi↔Wi-Fi, Wi-Fi↔mobile, mobile↔
mobile).

Implemented (all new files under `lib/multiplayer/`, zero new packages — pure
`dart:io` WebSockets):

- **`relay_protocol.dart`** — strict, versioned relay frame codec (`HOST`,
  `REGISTERED`, `LOOKUP`/`LOOKUP_ACK`/`LOOKUP_ERR`, `JOIN`/`JOIN_ACK`/`JOIN_ERR`,
  `SEND`/`PEER`/`PEER_JOINED`/`PEER_LEFT`, `KICK`, `LEAVE`, `ERR`). Deterministic
  canonical JSON; unknown versions/types and malformed frames are rejected without
  throwing. `RelaySendFrame` carries a member-id target (`host`, a member id, or
  broadcast) plus an **opaque** game-protocol payload the relay never parses.
- **`relay_server.dart`** — in-process, embeddable `RelayServer`: host registers a
  session (sid + 6-digit code + display name + player limit); clients join by sid
  (QR) or resolve a code (`LOOKUP`); the relay routes broadcast/unicast frames
  between members and reports peer join/leave/kick to the host so its virtual
  connections mirror the old per-client TCP connections. Stores **routing state
  only** — never game data. TTL sweep (default 30 min), max sessions, full-session
  rejection, host-loss tears the session down for every member, a kicked member's
  socket is actively closed, and no malformed frame can take the relay down.
- **`relay_transport.dart`** — `RelayMultiplayerTransport` implements the same
  `MultiplayerTransport` interface as `TcpMultiplayerTransport`, plus
  `RelayTransportServer` (host-side: one virtual `TransportConnection` per relay
  member) and `RelayTransportConnection` (client side). **The session layer above
  is transport-agnostic and needed zero changes** — host authority, protocol,
  privacy, heartbeats, reconnect, and resync all operate on `TransportConnection`.
  `lookupJoinCodeOnRelay()` replaces UDP-beacon code resolution.
- **`relay_config.dart`** — the relay endpoint constant the app targets.
- **`tool/relay_server_main.dart`** — standalone runner (`dart run
  tool/relay_server_main.dart` or `dart compile exe`) for deploying the relay.
- **`session.dart`** — `ClientSession.joinRelay()` (relay join with typed failure
  mapping) and `HostSession.start()` now passes `joinCode`/`displayName` through;
  a lobby-stage reconnect (game not started) re-adds the reclaimed player to the
  roster.
- **`remote_driver.dart`** — remembers the relay URL and reconnects through it
  (no LAN dependency for internet sessions).
- **`join_payload.dart`** — **v2 QR payload** `{v, t: TKJOIN, sid, code, relay}`:
  the relay endpoint replaces the LAN IP/port. The payload remains a locator: no
  cards, hands, deck, save data, history, or player identity, and the host still
  validates every join through the normal protocol. The 6-digit code stays a
  locator, not a credential.
- **Lobby UX** — QR/code join is relay-first. Nearby-games (UDP multicast) and the
  manual IP entry remain, collapsed under the **For Nerds** section ("Advanced
  options for curious turtles.") for debugging/fallback only; normal users never
  see networking details.

**Deployment (required for real internet play):** a relay instance must be reachable
at the URL in `relay_config.dart`. It is a single stateless-ish Dart process
(in-memory sessions, TTL-swept; no database): `dart compile exe tool/relay_server_main.dart`
and run it on any VPS/PaaS that allows WebSocket upgrades (typical small VPS ≈
$4–5/mo; the free tiers of most PaaS with WebSocket support also suffice). At a few
KB per frame of already-sanitized state and no storage, the free-tier footprint is
small. The relay is intentionally **not** an authentication service: the 6-digit code
is a locator; the host remains the authority for joins, identity, actions, and
privacy. The relay's coarse guards (session membership, max players, unknown-target
rejection, malformed-frame dropping) complement, never replace, host validation.

**Why no new package:** `WebSocket.connect`/`WebSocketTransformer` are built into
`dart:io`; the relay protocol and server are ~600 lines of in-repo Dart. No third-party
runtime dependency, no license risk.

**Privacy over the relay:** identical to LAN play — the relay forwards already-
sanitized public state and recipient-specific `PRIVATE_UPDATE` unicasts, and never
sees `GameState`, cards, deck, or save data. Wire-level tests decode every frame each
client receives and prove the only card-bearing channel is the per-recipient private
update.

**Remaining gap (M18.6):** real-device acceptance across mixed networks
(Wi-Fi ↔ mobile data) and a *public* relay instance are still outstanding — no
physical devices or a public endpoint are available in this environment; all
verification so far is in-process loopback over real WebSockets plus a compiled,
standalone relay exercised by `tool/relay_smoke_test.dart`. See
`m18-relay-deployment.md` for the exact deployment commands and
`m18-mixed-network-qa.md` for the two-phone acceptance matrix.

### 7.5 M18.6 — public relay deployment (recorded 2026-08-12)

M18.6 makes the relay deployable as a standalone public WebSocket service with
the minimum necessary changes — no new packages, no backend framework, no auth:

- **`lib/multiplayer/relay_server_app.dart`** — the testable process wrapper:
  configuration from `RELAY_BIND_ADDRESS`, `RELAY_PORT`, `RELAY_MAX_SESSIONS`,
  `RELAY_SESSION_TTL_MINUTES` (defaults → env → CLI flags), graceful
  SIGINT/SIGTERM shutdown (async signal errors contained — SIGTERM is
  unsupported on Windows), and a timestamped lifecycle logger.
- **`lib/multiplayer/relay_server.dart`** — optional `onLog` seam emitting
  **routing metadata only** (connect/disconnect, session register/close, member
  join/leave). The join code is never logged and payloads are never inspected,
  so game/private state can never appear in logs; regression-tested in
  `test/multiplayer/relay_logging_test.dart`.
- **`tool/relay_server_main.dart`** — thin wrapper; `dart compile exe` produces a
  self-contained binary. **`tool/relay_smoke_test.dart`** exercises a live relay
  process independently (host register, code lookup, join, bidirectional opaque
  routing, host-loss teardown).
- **New tests**: duplicate-join rejection, multi-session isolation, relay
  shutdown/restart, app config precedence + graceful-stop lifecycle, and
  LOOKUP invalid-code rejection.
- **UX fixes**: removed the last user-facing "same Wi-Fi network" wording
  (menu, host-lobby form, relay join-failure message) — normal users only see
  code/QR flows; LAN discovery and manual IP remain collapsed developer
  options.
- **Docs**: `m18-relay-deployment.md` (compile/run/deploy/app-config/APK
  commands) and `m18-mixed-network-qa.md` (12-row two-phone acceptance matrix).

Deployment target: any VPS/PaaS that supports WebSocket upgrades, with Caddy
(or nginx) terminating TLS in front so the app reaches it over `wss://`. The
6-digit code remains a locator, not a credential; no authentication is added.

### 7.6 M18 milestone progression (release record)

| Milestone | Delivered | Recorded in |
| --- | --- | --- |
| **M18.1** — architecture & transport discovery | Transport comparison (BLE/Wi-Fi Direct/LAN), topology, privacy model, dependency research, non-goals | §1–§6, §11, §17, §18 |
| **M18.2** — protocol + `GameDriver` foundation | Message codec (`protocol.dart`/`protocol_codec.dart`), `GameDriver`/`LocalDriver` seam, session layer, manifest permissions, loopback tests | §9–§10, §1.1 |
| **M18.3** — LAN transport & discovery | TCP transport (write-queue hardened), UDP multicast beacon discovery (no `multicast_dns`), multicast lock, manual-IP fallback | §5.3, §7.2, §8 |
| **M18.4** — remote gameplay, reconnection, host loss | `RemoteDriver` + `RemoteGameView` over the wire, `PublicStateView`/`PrivateStateView`, `ACTION_REQUEST`/resync, reconnection overlay, host-loss teardown | §11–§14, `remote_driver.dart` |
| **M18.5** — QR/code join UX | 6-digit join codes, v1/v2 QR payloads, `qr_flutter` + `mobile_scanner`, relay-first lobby, collapsed developer options, join-failure UX | §7.3, `join_code.dart`, `join_payload.dart` |
| **M18.6** — relay & mixed-network support, production-readiness | Dumb WebSocket relay (`relay_server.dart`), deployable process (`relay_server_app.dart`, `tool/relay_server_main.dart`), v2 QR payload, relay logging seam, deployment + two-phone QA docs, smoke test | §7.4–§7.5, `m18-relay-deployment.md`, `m18-mixed-network-qa.md` |

**Release status (v1.2.0):** LAN/local transport and the relay transport are
both implemented and covered by in-process loopback tests (real TCP and real
WebSockets). A **deployed public relay is required** for actual
internet/mixed-network play, and physical two-device verification against
such a relay has **not yet been performed** in this environment — see
`m18-mixed-network-qa.md` for the acceptance matrix.

## 8. Android permissions / requirements

Implemented manifest changes (M18.3 + M18.5):

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
```

- `INTERNET` is required for any socket use (currently absent; debug builds inject it, release builds need the explicit declaration).
- `CHANGE_WIFI_MULTICAST_STATE` is a normal permission (auto-granted) needed to acquire the multicast lock for mDNS reception on Android.
- Min SDK: **24** (Flutter default) — sufficient for TCP + mDNS. No min-SDK bump.
- iOS (later): `NSLocalNetworkUsageDescription` and `NSBonjourServices` (`_turtleking._tcp`) in Info.plist.

## 9. Session lifecycle

```
Host: CreateSession (advertise via mDNS) → [wait for joins]
Client: Discover (mDNS) / Manual IP → JOIN_REQUEST → JOIN_ACCEPT/REJECT
  → roster full / host locks → HOST: GAME_START (build GameState, broadcast public snapshot)
  → play: ACTION_REQUEST ⇄ ACTION_ACCEPTED/REJECTED + STATE_UPDATE broadcast (+ PRIVATE_UPDATE)
  → game completes (host GameState.gameComplete) → SESSION_END (reason: completed)
  → host leaves / lost → SESSION_END (reason: host-left) for all
```

- Join order = roster order = play order (matches the pass-and-play rule).
- A session is locked once the game starts (no mid-game joins).
- Leaving mid-game: a client leaving is a disconnection event (pause + resync on return, §13); the host leaving ends the session (§14).

## 10. Protocol design

JSON messages over a newline-delimited TCP stream, wrapped in a small envelope:

```json
{ "v": 1, "type": "STATE_UPDATE", "seq": 42, "sessionId": "…", "body": { … } }
```

- `seq` is a monotonically increasing per-sender counter used for idempotency and ordering.
- Message-size budget: tiny (< 1 KB typical; the largest, the reveal broadcast, is a few KB — well under any MTU concern for TCP).

| # | Message | Sender → Receiver | Purpose | Minimum fields | Private info? | Idempotent | Ack |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `DISCOVER` (mDNS) | host → all | advertise session | service type, instance name | no | n/a | n/a |
| 2 | `JOIN_REQUEST` | client → host | request a seat | player name | no | yes (by client seq) | yes |
| 3 | `JOIN_ACCEPT` | host → client | assign identity | sessionId, playerId, color, roster | no | yes | implicit |
| 4 | `JOIN_REJECT` | host → client | refuse | reason (name taken / full / locked) | no | yes | no |
| 5 | `ROSTER_UPDATE` | host → all | sync roster | roster (id/name/color, order) | no | yes | no |
| 6 | `GAME_START` | host → all | begin play | gameId, initial public state | no | yes | no |
| 7 | `ACTION_REQUEST` | client → host | propose an action | action (reveal/pass/holdOut/yamada/startNextRound), playerId | no | yes (by client seq) | yes |
| 8 | `ACTION_ACCEPTED` | host → requester | confirm | action, seq, new stateSeq | no | yes | no |
| 9 | `ACTION_REJECTED` | host → requester | refuse | action, seq, reason | no | yes | no |
| 10 | `STATE_UPDATE` | host → all | broadcast public state | stateSeq, public state (or delta) | **no** | yes | no (heartbeat + resync cover loss) |
| 11 | `PRIVATE_UPDATE` | host → one client | deliver own visible card | playerId, round, card, stateSeq | **yes — the only private message** | yes | yes |
| 12 | `RESYNC_REQUEST` | client → host | recover after reconnect/miss | playerId, sessionId, lastStateSeq | no | yes | yes |
| 13 | `RESYNC_RESPONSE` | host → client | full snapshot | stateSeq, full public state (+ pending private card if due) | no (card part is private unicast) | yes | no |
| 14 | `HEARTBEAT` | both | keepalive/liveness | seq | no | yes | no |
| 15 | `DISCONNECT` | either | announce leave | playerId, reason | no | no | no |
| 16 | `SESSION_END` | host → all | terminate | reason (completed / host-left / error) | no | yes | no |

**Design notes**

- Action requests are the *only* client-initiated gameplay messages. The host validates them with the existing `GameState` guards (turn ownership, phase, elimination) — the same atomic semantics already tested.
- `PRIVATE_UPDATE` is sent point-to-point only to the owning client, only when the rules entitle the player (right after their own `reveal` is accepted, and after a YAMADA redeal). It carries exactly one card. It is never broadcast.
- Reveal results: when the round resolves by reveal, the host broadcasts every revealed hand (both cards per player) — the rules make all hands public at that moment.

## 11. Privacy model

**Golden rule: only information the game rules make visible to a player may cross the network to that player.**

| Information | May cross? | How |
| --- | --- | --- |
| Player identity (id/name/color), roster, order | ✅ public | ROSTER_UPDATE / STATE_UPDATE |
| Current turn, viewing progress, pouring phase | ✅ public | STATE_UPDATE |
| Round number, cup size, drinks (lifetime/round), called-YAMADA flags | ✅ public | STATE_UPDATE (rules make these visible) |
| Eliminations, final result, round results | ✅ public | STATE_UPDATE |
| `GameEvent` history | ✅ public | already card-identity-free by design |
| All hands at the group reveal | ✅ public, broadcast | only after the rules authorize the reveal |
| A player's **own visible card** | ✅ private unicast | `PRIVATE_UPDATE`, only to that player, only at their reveal / after a YAMADA redeal |
| A player's own **hidden second card** | ❌ never (until reveal) | stays on the host; not even sent to its owner |
| Any other player's visible/hidden cards | ❌ never | — |
| Remaining deck order | ❌ never | host-only (used by `GameState`, never serialized) |
| Save document (`GameSaveCodec`) | ❌ never | contains all hands + deck; local-only, unchanged |
| Full `GameState` internals | ❌ never | only the sanitized public view is serialized |
| Audio/feedback events | not transmitted | each device plays its own local feedback on ACTION_ACCEPTED/state |

**Enforcement plan (M18.2+ tests):**

- A dedicated `PublicStateView` serializer built **only from public getters** (never from `handOf`/`visibleCardOf`/`remainingDeck`), with a test that asserts no card field exists anywhere in its JSON.
- Tests that run two hosts and a client against a malicious payload proving `ACTION_REQUEST` can't smuggle card data.
- Tests proving `PRIVATE_UPDATE` is delivered only to the correct player id, and that the hidden second card never appears in any broadcast or snapshot.

## 12. State synchronization strategy

- **Host-authoritative, command + state hybrid.**
- Clients render `RemoteGameView` — a read-only facade over the sanitized public state; they never run rules.
- Host broadcasts a **full public-state snapshot** after each accepted action for M18.2 (a whole game state is only a few hundred bytes; simplicity wins). Deltas are a later optimization if profiling demands it.
- Ordering: the host assigns `stateSeq`; clients apply in `stateSeq` order and ignore stale/duplicate messages (idempotent by seq).
- Private state: `PRIVATE_UPDATE` pairs with the stateSeq it belongs to; a client stores its own card for the round and clears it on round change / redeal per the host's state.

## 13. Reconnection strategy

1. Client detects socket drop (TCP error / heartbeat timeout).
2. Client shows a non-blocking "Reconnecting…" overlay; the host keeps its seat reserved and may continue (with the player skipped for that turn or the turn paused — decided in M18.2 implementation; the rules engine is untouched either way because the host simply holds the action).
3. Client reconnects TCP, sends `RESYNC_REQUEST` (playerId + lastStateSeq).
4. Host responds `RESYNC_RESPONSE` with the full public snapshot (+ a `PRIVATE_UPDATE` if a card is currently due to that player).
5. Client rebuilds `RemoteGameView` from the snapshot and resumes.
6. Long absence / 3 failed attempts → host may free the seat (M18.4 UX decision); a game with fewer than 2 connected players cannot progress anyway.

Because the host is authoritative and never relied on the client for state, no client-side state is ever trusted during resync — a full snapshot always wins.

## 14. Host-loss strategy

- **Explicit host-loss behavior (v1): if the host leaves or drops, the session ends.** The host owns `GameState` and the roster; there is no shared state from which a client could legitimately continue.
- Host declares `SESSION_END(reason: host-left)` when it can (explicit exit); when it drops abruptly, clients detect the socket loss + heartbeat timeout and show "The host left — session ended".
- **Host migration is an explicit non-goal for M18.2–M18.4.** It would require re-dealing or transferring the private deck to a new host — a large, privacy-sensitive change. It is recorded as a possible future milestone (§16) if product demand appears.

## 15. Testing strategy

No fake "networking tests" with no value. Instead:

- **Transport abstraction**: a small `SessionTransport` interface (send/stream/close) so tests inject an in-memory fake or loopback sockets.
- **Loopback integration tests (no hardware)**: start a host `ServerSocket` on `127.0.0.1`, connect N clients with the real codec over real TCP, play full games (view → pour → YAMADA/reveal → elimination → Turtle King), assert host `GameState` and every client view agree at each step and at game end.
- **Protocol codec tests**: round-trip every message type; reject malformed/unknown versions; assert idempotency semantics.
- **Privacy tests**: assert no card/rank/suit field in any broadcast or snapshot JSON; assert `PRIVATE_UPDATE` reaches only the intended player; assert the hidden second card never leaves the host until the reveal.
- **Determinism**: same seed + same action script ⇒ identical outcome on all views (reuses existing determinism test patterns).
- **Rebuild safety**: the multiplayer game screen must not fire feedback on rebuild (existing M17 regression pattern extended).
- **Pass-and-play**: entire existing suite must stay green (LocalDriver path is the current code).

## 16. Original M18.2–M18.4 implementation roadmap

The table below is the *original* M18.2–M18.4 plan. The actual delivery
progression (including the M18.5 UX and M18.6 relay milestones) is recorded
in §7.6. The plan's scoping differs slightly from what shipped (the
`multicast_dns` package was replaced by the in-repo beacon protocol — §7.2 —
and the QR/code join UX and relay became their own milestones).

| Milestone | Scope |
| --- | --- |
| **M18.2 — Session & transport foundation** | Add `multicast_dns` (as originally planned); manifest permissions; `lib/multiplayer/` with protocol codec + message types; TCP `SessionTransport`; host advertisement + client discovery (manual IP fallback); lobby UI (create session / join session, roster display, join accept/reject); loopback + codec + privacy tests. No gameplay changes. |
| **M18.3 — Gameplay over the wire** | `GameDriver` abstraction (LocalDriver = today's code; RemoteDriver = request/apply); `PublicStateView` serializer; host broadcast + client `RemoteGameView`; `PRIVATE_UPDATE` unicast (own visible card); full-game loopback integration test; feedback fires locally on accepted actions (no transmission of audio). |
| **M18.4 — Resilience & release** | Heartbeat, reconnection overlay, `RESYNC_REQUEST/RESPONSE`; host-loss UX; seat-release policy; real-device verification (physical phones), release builds, APK size/perms diff, docs, final review. |

## 17. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| mDNS unreliable on some Android Wi-Fi (APs block multicast) | LAN discovery is a collapsed developer fallback only; the normal join path is QR/code over the internet relay |
| Host is a single point of failure | Explicit host-loss UX; migration is a documented non-goal |
| Plaintext private card in transit | Accepted for trusted play; the relay is a dumb forwarder that never stores payloads; TLS termination (wss) is the documented deployment setup |
| Relay unavailable or misconfigured | Lobby shows a clear configuration/connection error; LAN developer fallback still exists |
| Turn blocked when a client drops | Reserved seat + resync; host continues holding actions until the player returns |
| Latency perception | Actions are validated locally-echoed via ACTION_ACCEPTED; feedback plays on acceptance (not on broadcast), matching M17 timing goals |
| Dependency drift | Runtime packages are pinned and few (`shared_preferences`, `audioplayers`, `qr_flutter`, `mobile_scanner`); networking is SDK-only |

## 18. Explicit decisions that must remain unchanged

These are contractual for the whole of Phase 18:

1. **`GameState` is the single authoritative rules engine, on the host.** Clients never compute rules.
2. **Network code transports commands and sanitized state only** — never gameplay-rule logic.
3. **Pass-and-play (LocalDriver) remains complete and unchanged**, always available offline with zero setup.
4. **Card privacy is absolute**: only a player's own visible card (private unicast, rule-authorized) and the authorized group reveal may cross the network.
5. **`GameSaveCodec` and the save document never cross the network.**
6. ~~**No internet, no servers, no accounts** — offline LAN only.~~ **Revised by M18.6:** a minimal dumb WebSocket relay is the production transport (no accounts, no matchmaking, no stored game data, no auth — the 6-digit code stays a locator, not a credential).
7. **`GameFeedback` stays local**; no audio events are transmitted.
8. **No new gameplay rules, settings, or history/replay changes** may be introduced by the multiplayer work.
9. **Host migration is out of scope** for M18 (through M18.6).
10. **No second feedback/settings/state system** — the M17 `GameFeedback` seam and `SettingsStore` remain the only ones.
