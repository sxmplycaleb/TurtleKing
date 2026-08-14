# M18.6 — Mixed-Network Acceptance (manual QA)

Goal: prove two phones can play Turtle King **from anywhere with an internet
connection** — Wi-Fi ↔ Wi-Fi, Wi-Fi ↔ mobile data, mobile data ↔ mobile data —
with the 6-digit code and QR as the primary join mechanisms, and LAN
networking hidden behind developer options.

> **Status: not yet executed.** This matrix is the acceptance plan for
> physical two-phone verification against a deployed public relay. A
> public relay is now live at `wss://turtleking.onrender.com` (health
> check passes; see `m18-relay-deployment.md`), but no physical devices
> are available in this environment, so every row below is still
> **unfilled** — do not treat any row as passed. All verification to date
> is in-process loopback (real TCP/WebSockets) plus
> `tool/relay_smoke_test.dart` against a local relay.

Prerequisites:

- A **public relay endpoint** deployed per `docs/multiplayer/m18-relay-deployment.md`
  (or a LAN-reachable relay for a first pass; the mixed-network rows require
  public reachability).
- Two APKs built with that endpoint:
  `flutter build apk --debug --dart-define=RELAY_URL=wss://<relay-host>`
- Two physical phones (Android), one acting as **host**, one as **client**.
- A second Wi-Fi network (or a phone with mobile data) to simulate the other
  side of the internet.

Record **Pass**/**Fail** for every row. Any Fail is a blocker for M18.6
completion; note the observed behavior next to the fail.

---

## 1. Host on Wi-Fi / client on mobile data

- **Setup:** Host phone on home Wi-Fi. Client phone on mobile data
  (Wi-Fi off). Both have the relay-enabled APK.
- **Action:** Host: New Game → Multiplayer → Host Game. Client: New Game →
  Multiplayer → Join Game → enter the host's 6-digit code.
- **Expected result:** Client joins, both see the roster, game starts and
  plays normally.
- **Pass/Fail:** ☐

## 2. Host on mobile data / client on Wi-Fi

- **Setup:** Host phone on mobile data (Wi-Fi off). Client phone on home
  Wi-Fi.
- **Action:** Host: New Game → Multiplayer → Host Game. Client scans the
  host's QR code (or enters the code) from the Wi-Fi network.
- **Expected result:** Client joins and plays normally.
- **Pass/Fail:** ☐

## 3. Both on mobile data (if feasible)

- **Setup:** Two phones on mobile data from two different carriers (same
  carrier also acceptable if both get public IPs / CGNAT).
- **Action:** Host starts a session; client joins by code.
- **Expected result:** Session works — this is the hardest case for
  NAT/CGNAT and proves the relay inverts connectivity properly.
- **Pass/Fail:** ☐

## 4. QR join

- **Setup:** Host session running; client with camera permission granted.
- **Action:** Client taps **Scan QR Code** and points at the host's QR.
- **Expected result:** "Connecting…" appears immediately, the client joins
  without typing anything, roster shows both players.
- **Pass/Fail:** ☐

## 5. 6-digit code join

- **Setup:** Host session running; code displayed grouped as `483 729`.
- **Action:** Client taps **Join Game → Enter code**, types the six digits.
- **Expected result:** Code resolves fast (a few seconds), client joins.
- **Pass/Fail:** ☐

## 6. Wrong code

- **Setup:** Host session running.
- **Action:** Client enters a wrong-but-well-formed 6-digit code (e.g.
  `999999`).
- **Expected result:** Fails fast with "No game found with this code" (not a
  long timeout); the client can correct the code and join.
- **Pass/Fail:** ☐

## 7. Expired / unavailable session

- **Setup:** Host starts a session, then the host's app is killed (or the
  session is ended). Wait ~30 s for the relay sweep (or use a session ended
  earlier).
- **Action:** Client enters the old code or scans the old QR.
- **Expected result:** Client gets a clear "Game unavailable — this session
  no longer exists" / "The session has ended" style message; no crash, no
  hang.
- **Pass/Fail:** ☐

## 8. Full game

- **Setup:** Host + one client joined over mixed networks (Wi-Fi ↔ data).
- **Action:** Play a complete game: view rounds, pour/YAMADA, eliminations,
  Turtle King, next rounds. The **host's** device plays too.
- **Expected result:** Every action applies on the host's authoritative
  state; both devices stay in sync; the game completes.
- **Pass/Fail:** ☐

## 9. Private-card privacy

- **Setup:** Host + two clients over the relay (or host + one client).
- **Action:** During the viewing phase, each player reveals their own card.
  The **other** player's screen must not show it.
- **Expected result:** Each player sees only their own visible card; no
  hidden second card ever appears on another device until the authorized
  group reveal.
- **Pass/Fail:** ☐

## 10. Client reconnect

- **Setup:** Host + client mid-game over the relay.
- **Action:** Toggle the client's Wi-Fi off then on (or enable airplane mode
  briefly). The client should show a "Reconnecting…" state and rejoin.
- **Expected result:** The client reconnects through the relay, reclaims its
  player identity, resyncs to the current public state, and play resumes
  without a duplicate player.
- **Pass/Fail:** ☐

## 11. Host disconnect

- **Setup:** Host + client mid-game over the relay.
- **Action:** Kill the host's app (or lose its connection).
- **Expected result:** The client sees "The host left — session ended"
  promptly; no hang, no crash.
- **Pass/Fail:** ☐

## 12. Multiple simultaneous games

- **Setup:** Two host phones, each hosting a session on the same relay
  (different 6-digit codes).
- **Action:** Two clients join — one per session. Exchange frames in both
  sessions at the same time.
- **Expected result:** Sessions are fully isolated: codes resolve to the
  right host, routing never crosses between games, both games play normally.
- **Pass/Fail:** ☐

---

## Post-run summary

- Fill in every Pass/Fail row above.
- **All Pass** → M18.6 mixed-network acceptance is complete for this build.
- Any **Fail** → reproduce, capture the client/host behavior, and file the
  fix before declaring M18.6 done. Do not weaken or delete existing tests.
