# M19 — Bluetooth Multiplayer: Architecture & Transport Record

**Status:** implemented (in-process tested) — physical two-device verification
outstanding. This milestone adds Bluetooth Low Energy as a **third local
transport** beside the LAN/TCP transport and the internet relay. It does not
change the session layer, the protocol, host authority, privacy boundaries,
or any relay behavior.

## 1. Goals and non-goals

**Goals**

- Local/offline multiplayer between nearby phones with **no internet and no
  Wi-Fi** — a genuine alternative to relay play, not a fallback.
- Reuse the existing session/game protocol and every multiplayer rule
  unchanged (host-authoritative `GameState`, `PublicStateView` /
  `PrivateStateView`, stale-action protection, reconnection, host loss).
- Keep the normal user flow simple: *Host Game → Bluetooth* and *Join Game →
  Nearby (Bluetooth) → pick a host*. No BLE terminology in normal UI.
- Android and iOS from day one, with the platform differences contained in
  one adapter file.

**Non-goals**

- Bluetooth Classic / RFCOMM (iOS forbids third-party Classic; see §3).
- Changing the relay, LAN transport, discovery, or QR/code join flow.
- Replacing the game's authoritative state model or the privacy model.

## 2. Transport boundary (what is reused unchanged)

`lib/multiplayer/transport.dart` defines the interface in terms of complete
JSON message strings — `TransportConnection` (`Stream<String> incoming`,
`send`, `isOpen`, `close`) and `TransportServer` (`Stream<TransportConnection>
connections`, `port`, `close`). The BLE transport implements exactly this
interface:

- `BleMultiplayerTransport implements MultiplayerTransport`
- `BleTransportServer implements TransportServer` (host side)
- `BleClientTransportConnection implements TransportConnection` (client side)

Consequences:

- `HostSession` / `ClientSession` (`session.dart`) are untouched apart from
  two seams: `ClientSession.join` gained an optional
  `socketErrorMessage` (so BLE can say "make sure Bluetooth is on" instead
  of the same-Wi-Fi wording) and `ClientSession` already accepted a
  `transport:` parameter, which `RemoteDriver` now fills on rejoin.
- `RemoteDriver` gained two optional fields, `rejoinTransport` and
  `rejoinHostAddress`, so reconnection uses the same BLE transport and the
  peer identifier as the address (BLE has no IP/port).
- The protocol codec, join handshake, roster, action validation, resync, and
  heartbeat messages are byte-identical over BLE.

## 3. Technology choice: BLE (not Classic, not Nearby)

| Option | Finding |
| --- | --- |
| **Bluetooth Classic / RFCOMM** | Rejected. iOS **forbids** Classic RFCOMM/SPP for third-party apps (CoreBluetooth exposes BLE only; Classic needs MFi). Android-only Classic would split the platform story and add pairing friction. |
| **BLE (GATT)** | **Chosen.** Host = GATT peripheral (one service, two characteristics), clients = GATT centrals. Android and iOS both support central and peripheral roles; message sizes (a few hundred bytes of JSON) fit comfortably in 20-byte MTU chunks. |
| **Nearby Connections / platform P2P** | Rejected for now. No single cross-platform Flutter package with Android + iOS support; Wi-Fi Direct is Android-only and mDNS/LAN already exists. BLE keeps everything inside one maintained package. |

### 3.1 Package: `bluetooth_low_energy ^6.2.1`

- MIT license (no commercial trap — `flutter_blue_plus` moved to a
  source-available license requiring payment for for-profit use, and is
  central-only anyway; the M18 record rejected it on both grounds).
- Supports **both** central and peripheral roles on Android **and** iOS —
  the only maintained Flutter BLE package that does.
- API shape: `CentralManager` (scan, connect, GATT discovery, notify
  subscription, MTU) + `PeripheralManager` (GATT service, advertise,
  notifications, connection state). The adapter wraps both.
- minSdk 24 matches the project's existing Android floor.
- Only `lib/multiplayer/ble/plugin_ble_adapter.dart` imports the package;
  everything else is pure Dart and unit-tested with an in-memory fake.

## 4. GATT service design

One primary service, vendor UUID range (`0xFC00`):

| Characteristic | UUID | Direction | Properties |
| --- | --- | --- | --- |
| Write | `0xFC01` | client → host | write (with response) |
| Notify | `0xFC02` | host → client | notify |

- The host **advertises** the service UUID **only** — deliberately no
  game name. The Android plugin implements an advertised name by renaming
  the device itself (`BluetoothAdapter.setName`), which both renames the
  user's phone to the game name and hangs forever on repeat hosts (once the
  name is unchanged, `ACTION_LOCAL_NAME_CHANGED` never broadcasts and the
  plugin's `setName` await never completes). Joiners match on the service
  UUID and see the fallback game name; never a session id, join code,
  player, card, or game data (see §10).
- A client is admitted as soon as it subscribes to notifications — a
  cross-platform "I'm here" signal. Android additionally reports
  connect/disconnect via `connectionStateChanged`; iOS has no
  peripheral-side disconnect callback (covered by the heartbeat, §9.2).
- Writes are `withResponse`; every request is answered (`respondWriteRequest`)
  so the client's write never hangs.

## 5. Framing: chunked messages over MTU

BLE notifications/writes are small (default 20 bytes). `ble_framing.dart`
splits and reassembles the existing JSON messages:

```
FIRST chunk:        [0x01] [len 4 bytes BE] [message bytes ...]
CONTINUATION chunk: [0x02] [message bytes ...]
```

- One chunk carries the length header; continuations carry a header byte and
  the next slice up to the negotiated chunk size.
- The assembler enforces a 256 KB bound (mirrors the TCP transport's limit),
  rejects continuation-without-start, unknown headers, and over-length
  messages with a `FormatException` — the transport treats that as a
  protocol violation and **drops the peer's link** (the client sees its
  disconnect stream fire, same as a TCP server closing on garbage).
- **Sends are serialized per connection** (a write queue): the session layer
  fires messages unawaited, and two concurrent chunked sends would
  interleave and corrupt framing. The TCP/relay transports serialize the
  same way; the BLE transport does too.

## 6. Discovery design

`BleSessionDiscovery implements SessionDiscovery` (same interface as the LAN
UDP beacon discovery), so the join lobby treats Bluetooth like any other
local source of `DiscoveredSession`s.

- The advertisement carries **no structured payload**, so the session id and
  join code cannot ride in it. The discovered session uses the peer's BLE
  identifier as both `hostAddress` and a placeholder session id; the host's
  real id is adopted during the normal JOIN handshake — exactly like a
  manual-IP LAN join.
- The join code stays the relay path's locator; BLE sessions are joined from
  the nearby list, not by code.
- Advertising is started by `BleMultiplayerTransport.startServer` (the GATT
  server must exist before advertising); `BleSessionDiscovery.advertise` is
  a parity no-op and `stop()` stops advertising without tearing down the
  server (the host still delivers SESSION_END to joined clients).

## 7. Host flow

1. Host Game → **Bluetooth** → `ensureAuthorized()` (Android runtime
   prompt; iOS prompts on first use) → adapter-state checks (off /
   unsupported / denied surface friendly messages).
2. `HostSession(transport: BleMultiplayerTransport(adapter),
   discovery: BleSessionDiscovery(adapter), joinCode: null)` — no relay, no
   code.
3. `session.start(...)` → GATT service published → advertising begins →
   `BleTransportServer` delivers one virtual `TransportConnection` per
   connecting central (same shape as the relay's multiplexed server).
4. Normal join handshake, roster, gameplay — all session-layer logic,
   unchanged.

## 8. Client flow

1. Join Game → **Nearby (Bluetooth)** → `ensureAuthorized()` + state checks
   → `startScan()` filtered to the Turtle King service UUID.
2. Discovered hosts appear as a list (name + "Nearby game"); picking one
   calls `BleMultiplayerTransport.connect(hostAddress: peerId, port: 0)`.
3. Connect → GATT discovery → MTU request (Android) → subscribe to
   notifications **before** the first message (the host admits the peer on
   subscription) → normal `ClientSession.join` handshake → lobby → play.
4. `RemoteDriver` carries `rejoinTransport` + `rejoinHostAddress` so a
   reconnect rejoins over BLE (peer id), not over a LAN address.

## 9. Connection lifecycle

### 9.1 Host side

- `BleHostConnected` (notify subscription) admits a peer; `BleHostConnected`
  events for already-known peers are ignored (duplicate-subscription
  guard).
- `BleHostDisconnected` (Android `connectionStateChanged`) marks the
  connection closed; the session layer handles the member leaving.
- `dropPeer` disconnects a specific central — used when the host tears down
  a protocol-violating client's link.
- `close()` on the server stops advertising, removes the GATT service, and
  marks every member connection closed.

### 9.2 Liveness / silent peers

- The **session-layer heartbeat is unchanged** (5s interval / 15s timeout
  app-level `HEARTBEAT` messages) and runs over BLE exactly as over
  TCP/relay — heartbeat frames carry no data.
- iOS exposes **no peripheral-side disconnect event**, so a client that
  vanishes without a close (walked out of range, app killed) is reaped by
  the session heartbeat on both sides: the host's member connection times
  out and the roster updates; the client's own stream closes and the
  reconnection flow starts. This is the same heartbeat guarantee the relay
  fix (v1.2.1) relies on — no new mechanism, no new privacy surface.

### 9.3 Client side

- The central connection surfaces two streams: inbound chunks and a
  `disconnected` event (from the platform's connection-state stream). Both
  mark the link closed; `RemoteDriver` starts its normal reconnecting →
  resyncing flow, rejoining over BLE.
- `close()` is idempotent and cancels subscriptions.

## 10. Privacy and security

- **The advertisement is the service UUID only** (no name — see §4 for
  why; joiners show the fallback game name). No session id, join code,
  player identity, card, deck, or game data is ever advertised (the
  M18 QR/join-code locator discipline carried over).
- **Frames are opaque bytes** to the BLE stack; the platform never sees
  message content.
- **Session id adoption** happens inside the JOIN handshake (like a manual
  LAN join) — discovery never reveals which game a host is running beyond
  its display name.
- **No new authority**: clients never construct `GameState`; the host
  remains authoritative; `PublicStateView`/`PrivateStateView` isolation and
  stale-action protection are inherited unchanged.
- A **malformed-frame peer is dropped** (framing violation = protocol
  violation), so a misbehaving nearby device cannot wedge the session.
- Player names and discovery identifiers are **not** authentication — the
  host still validates every join through the normal protocol, and nothing
  in the discovery payload grants access.

## 11. Platform requirements

### Android (`android/app/src/main/AndroidManifest.xml`)

- `BLUETOOTH_SCAN` (with `neverForLocation`, `tools:targetApi="s"`),
  `BLUETOOTH_CONNECT`, `BLUETOOTH_ADVERTISE` (Android 12+); legacy
  `BLUETOOTH` / `BLUETOOTH_ADMIN` / `ACCESS_FINE_LOCATION`
  (`maxSdkVersion="30"`) below.
- `<uses-feature android:name="android.hardware.bluetooth_le"
  android:required="false"/>` — the app stays installable on BLE-less
  devices; relay/LAN still work there.
- The plugin's `authorize()` raises the runtime prompt(s) at the correct UX
  moment (host: ADVERTISE+CONNECT; client: SCAN+CONNECT).

### iOS (`ios/Runner/Info.plist`)

- `NSBluetoothAlwaysUsageDescription` — "Turtle King uses Bluetooth to host
  and join nearby multiplayer games without an internet connection."
- The OS prompts on first use; `BluetoothLowEnergyState.unauthorized`
  drives the same friendly permission-denied UI.

## 12. Testing strategy

- **Unit:** framing (chunk split/reassemble, edge sizes, malformed input) —
  `test/multiplayer/ble_framing_test.dart`.
- **Integration (in-memory BLE network):** `test/multiplayer/ble_fakes.dart`
  simulates a room of phones (scan/discover/connect/chunk delivery/
  disconnect) behind the same `BleAdapter` interface the plugin implements;
  `test/multiplayer/ble_transport_test.dart` drives the **real** session
  layer over real framing: host+join, gameplay, private-card isolation,
  host loss, reconnect, duplicate-join protection, malformed-frame
  rejection.
- **Regression:** the full existing suite (LAN, relay, offline, reconnect,
  host-loss, stale-action, privacy, UI flow) must stay green.
- **Physical (not yet performed):** two Android devices, host ↔ client,
  per `docs/multiplayer/m19-bluetooth-qa.md`.

## 13. Milestone record

| Milestone | Delivered |
| --- | --- |
| **M19.1** — Bluetooth foundation | `bluetooth_low_energy` dependency, `BleAdapter` seam, GATT service design, Android/iOS permissions |
| **M19.2** — discovery | `BleSessionDiscovery`, advertisement (service UUID only) |
| **M19.3** — connection/handshake | `PluginBleAdapter` connect flow (GATT discovery, MTU, notify subscription), typed errors |
| **M19.4** — transport/protocol | `BleMultiplayerTransport`/`BleTransportServer`/`BleClientTransportConnection`, chunked framing, serialized sends |
| **M19.5** — reliability | `RemoteDriver` rejoin over BLE (peer id), host-loss teardown, malformed-frame drop, iOS silent-peer reaping via heartbeat |
| **M19.6** — UX integration | Host Game → Bluetooth mode; Join Game → Nearby (Bluetooth) with permission/error states; join-failure wording |
| **M19.7** — physical-device QA | **Outstanding** — see `docs/multiplayer/m19-bluetooth-qa.md` |

**Release note:** Bluetooth is a new capability on top of v1.2.1; it is
tracked as M19 (a future minor release), not as part of the v1.2.x patch
line.
