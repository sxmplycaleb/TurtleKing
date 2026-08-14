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

> **Deployment status: LIVE at `https://turtleking.onrender.com`** — the
> Render Web Service is deployed, `GET /health` returns `200
> {"status":"ok"}`, and the relay passes the smoke test against the
> deployed WSS endpoint **except** host-loss, which is fixed by the
> heartbeat liveness change (this branch) and needs a redeploy of this
> branch to take effect on the public endpoint. All relay behavior is
> validated locally (compiled binary + `tool/relay_smoke_test.dart` + the
> automated relay test suite, including the heartbeat host-loss
> regression). **No two-phone mixed-network test has been performed.** Do
> not claim internet multiplayer is working until the deployed endpoint
> has been exercised from two physical devices on different networks (see
> `m18-mixed-network-qa.md`).

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

The relay detects a lost host by **heartbeat**, not by close frames: it
pings every connection every 2s and drops any that stays silent for 10s
(an app killed, a network drop, or a proxy that swallows WebSocket close
frames). Dropping the host tears its session down and closes every
member's socket — the smoke test's host-loss check allows for this
window, so it passes over both a direct path and a proxied internet
path.

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

### 3.3 Deploy on Render (container)

The repository root `Dockerfile` builds the relay as a production
container: a Dart SDK stage compiles `tool/relay_server_main.dart` into an
AOT executable (the relay is pure `dart:io` with zero external packages,
so no Flutter SDK is needed), and a minimal glibc stage runs it as an
unprivileged user. A Render Web Service connected to this repository picks
the `Dockerfile` up automatically.

**Render service configuration**

- **Build**: root `Dockerfile` (auto-detected).
- **Port**: Render injects a platform-chosen `PORT`; the relay honors it
  (`RELAY_PORT` or `--port` still win — see the configuration table). No
  port setting is needed.
- **Health check**: path `/health`, expected status `200`. The relay
  answers `GET /health` with a static `{"status":"ok"}` that never
  contains sessions, join codes, players, or game data.
- **Environment** (all optional; defaults are safe):
  - `RELAY_BIND_ADDRESS=0.0.0.0` (the default; required so the platform's
    health check can reach the relay)
  - `RELAY_MAX_SESSIONS` (default `64`)
  - `RELAY_SESSION_TTL_MINUTES` (default `30`)
- **Instance**: any Free/Starter instance is enough for a party-game
  relay; sessions are in-memory, so keep the service running.

**URLs**

Render assigns a public HTTPS hostname, e.g. `<service-name>.onrender.com`.
Because Render terminates TLS, the app connects with:

```
wss://<service-name>.onrender.com
```

(no port — Render maps `:443` to the service's internal `PORT`; the relay
itself stays plain WebSocket behind the proxy, exactly like the Caddy setup
above.)

**Verify the deployed relay**

```bash
curl https://<service-name>.onrender.com/health   # → {"status":"ok"}
dart run tool/relay_smoke_test.dart wss://<service-name>.onrender.com
# → SMOKE TEST PASSED
```

Then build the app with
`--dart-define=RELAY_URL=wss://<service-name>.onrender.com` (step 5) and
run the mixed-network matrix (`m18-mixed-network-qa.md`).

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
| Port           | `RELAY_PORT`, or `PORT` (Render) | `--port <n>`            | `8787` |
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
- **Health checks**: `GET /health` returns a static `{"status":"ok"}`
  (never sessions, join codes, players, or game data — regression-tested in
  `test/multiplayer/relay_health_test.dart`); non-WebSocket requests to any
  other path return HTTP 426. Container platforms (Render) can point their
  health check at `/health`.
