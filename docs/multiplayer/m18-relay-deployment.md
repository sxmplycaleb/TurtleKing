# M18.6 — Public Relay Deployment

The internet multiplayer relay (`tool/relay_server_main.dart` +
`lib/multiplayer/relay_server.dart`) is a single, dependency-free Dart
process. It is a **dumb WebSocket router**: it holds session membership and
routes opaque game-protocol frames; it never parses game content, never
stores game state, and never sees cards/hands/deck/save data.

This document gives the exact commands to compile, run, deploy, and connect
the app to a public relay.

- Relay code: `lib/multiplayer/relay_server.dart` (server),
  `lib/multiplayer/relay_server_app.dart` (process: config + shutdown),
  `lib/multiplayer/relay_protocol.dart` (wire protocol)
- Runner: `tool/relay_server_main.dart`
- App endpoint: `lib/multiplayer/relay_config.dart` (`RELAY_URL`)

> **Deployment status: IMPLEMENTED, not yet DEPLOYED, not yet PHYSICALLY
> VERIFIED.** The relay is implemented and validated locally (compiled
> binary + `tool/relay_smoke_test.dart` + the automated relay test suite),
> but **no public relay instance has been deployed** and **no two-phone
> mixed-network test has been performed** in this environment. The single
> external step — provisioning a VPS/PaaS and a domain, and running the
> steps below — requires infrastructure access that this environment does
> not have. Do not claim internet multiplayer is working until the deployed
> endpoint has been exercised from two physical devices on different
> networks (see `m18-mixed-network-qa.md`).

---

## 1. Compile the relay

```bash
dart compile exe tool/relay_server_main.dart -o build/relay_server
```

Produces a self-contained native executable (`build/relay_server.exe` on
Windows) with no runtime dependencies — copy it to any Linux VPS and run it.

## 2. Run it locally

From source:

```bash
dart run tool/relay_server_main.dart --port 8787
```

From the compiled binary:

```bash
./build/relay_server --port 8787
```

Verify it with the standalone smoke test (needs the relay running):

```bash
dart run tool/relay_smoke_test.dart ws://127.0.0.1:8787
```

Once a public endpoint exists, run the **same smoke test against the
deployed WSS endpoint** to prove the full internet path (TLS + WebSocket
upgrade + relay protocol) works end to end:

```bash
dart run tool/relay_smoke_test.dart wss://<real-relay-domain>
```

The smoke test expects `SMOKE TEST PASSED`; it exercises host
registration, code lookup (found + wrong-code), client join, opaque frame
routing in both directions, and host-loss teardown.

## 3. Run it on a public server

The relay binds `0.0.0.0:8787` by default and serves plain WebSocket
(`ws://`). For phones to reach it over the internet you need **TLS**, so the
app connects with `wss://`. The recommended, simplest setup is a small VPS
with **Caddy** (or nginx) in front of the relay:

```
Internet (wss://relay.example.com)
   │
 Caddy 443 → TLS termination → ws://127.0.0.1:8787
   │
 relay_server (binds 127.0.0.1:8787)
```

### 3.1 systemd unit

`/etc/systemd/system/turtle-king-relay.service`:

```ini
[Unit]
Description=Turtle King multiplayer relay
After=network.target

[Service]
Type=simple
User=relay
WorkingDirectory=/opt/turtle-king-relay
ExecStart=/opt/turtle-king-relay/relay_server
Environment=RELAY_BIND_ADDRESS=127.0.0.1
Environment=RELAY_PORT=8787
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now turtle-king-relay
sudo systemctl status turtle-king-relay
```

`SIGTERM` (sent by `systemctl stop`) triggers a graceful shutdown: every
session is closed, every member socket is closed, and the process exits
cleanly.

### 3.2 TLS with Caddy

`/etc/caddy/Caddyfile`:

```
relay.example.com {
    reverse_proxy 127.0.0.1:8787
}
```

Caddy issues and renews the certificate automatically and forwards WebSocket
upgrades transparently. No relay-side TLS configuration exists — the relay
stays plain `ws://` behind the proxy.

(nginx equivalent: `proxy_pass http://127.0.0.1:8787;` plus
`proxy_http_version 1.1;` and `proxy_set_header Upgrade $http_upgrade;`
`proxy_set_header Connection "upgrade";`.)

## 4. Configure the Flutter app with the public WSS endpoint

The endpoint is a **build-time constant** injected with `--dart-define` —
nothing is hard-coded and no secrets are committed.

```bash
flutter run --dart-define=RELAY_URL=wss://relay.example.com
```

The join code stays a **locator, not a credential**; no authentication is
added. When `RELAY_URL` is empty the lobby shows a clear configuration error
instead of failing silently.

## 5. Build the Android APK using that endpoint

```bash
flutter build apk --debug   --dart-define=RELAY_URL=wss://relay.example.com
flutter build apk --release --dart-define=RELAY_URL=wss://relay.example.com
```

The APK lands in `build/app/outputs/flutter-apk/`. Install it on phones and
test the mixed-network acceptance matrix
(`docs/multiplayer/m18-mixed-network-qa.md`).

---

## Configuration reference

Sources, in increasing precedence: **defaults → environment → CLI flags**.

| Setting        | Env var                     | CLI flag                    | Default |
| -------------- | --------------------------- | --------------------------- | ------- |
| Bind address   | `RELAY_BIND_ADDRESS`        | `--bind <addr>`             | `0.0.0.0` |
| Port           | `RELAY_PORT`                | `--port <n>`                | `8787` |
| Max sessions   | `RELAY_MAX_SESSIONS`        | `--max-sessions <n>`        | `64` |
| Session TTL    | `RELAY_SESSION_TTL_MINUTES` | `--session-ttl-minutes <n>` | `30` |

App-side (build-time, Flutter): `RELAY_URL` (`wss://…`).

## Logging & privacy

The relay logs **routing metadata only**: connection open/close, session
registered/closed, member joined/left. It never logs the join code and never
logs frame payloads — the relay cannot log game content because it never
inspects it (regression-tested in `test/multiplayer/relay_logging_test.dart`).
Log lines look like:

```
[2026-08-12 19:40:01] Turtle King relay listening on 0.0.0.0:8787
[2026-08-12 19:40:11] connect 203.0.113.7
[2026-08-12 19:40:11] session tk-1a2b3c registered
[2026-08-12 19:40:12] member m1 joined tk-1a2b3c
[2026-08-12 19:40:20] member m1 left tk-1a2b3c (left)
[2026-08-12 19:40:21] session tk-1a2b3c closed (host left)
[2026-08-12 19:40:22] shutting down
```

## Operational notes & known limits

- **Sessions are in-memory**: restarting the relay drops every session.
  Acceptable for a party-game relay; keep `Restart=always` for availability.
- **Slow clients**: frames are capped at 256 KB each; a stalled peer buffers
  its own outbound queue in memory but never blocks other members (sends are
  per-target fire-and-forget).
- **No database, no auth, no accounts.** The 6-digit code is a locator; the
  host remains the authority for joins, actions, and privacy.
- **Health checks**: the relay answers non-WebSocket requests with HTTP 426.
  A monitoring probe can rely on `wss://` upgrade success or TCP connect.
