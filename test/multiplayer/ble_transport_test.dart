import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/multiplayer/ble/ble_adapter.dart';
import 'package:turtle_king/multiplayer/ble/ble_discovery.dart';
import 'package:turtle_king/multiplayer/ble/ble_framing.dart';
import 'package:turtle_king/multiplayer/ble/ble_transport.dart';
import 'package:turtle_king/multiplayer/protocol.dart';
import 'package:turtle_king/multiplayer/protocol_codec.dart';
import 'package:turtle_king/multiplayer/remote_driver.dart';
import 'package:turtle_king/multiplayer/session.dart';
import 'package:turtle_king/multiplayer/transport.dart';
import 'package:turtle_king/player.dart';

import 'ble_fakes.dart';
import 'helpers.dart';

/// Waits until [condition] holds (polled, with a deadline).
Future<void> pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('pumpUntil condition never became true');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

const Duration kSlow = Duration(seconds: 10);

/// Starts a real [HostSession] hosted over the fake BLE network.
Future<({HostSession host, FakeBleAdapter hostAdapter, String hostId})>
startBleHost(
  FakeBleNetwork network,
  String sessionId, {
  String gameName = 'Turtle King Game',
}) async {
  final hostAdapter = FakeBleAdapter(network);
  final host = HostSession(
    sessionId: sessionId,
    transport: BleMultiplayerTransport(adapter: hostAdapter),
    discovery: BleSessionDiscovery(adapter: hostAdapter),
  );
  await host.start(displayName: gameName, hostName: 'Host', port: 0);
  return (host: host, hostAdapter: hostAdapter, hostId: hostAdapter.hostId!);
}

/// A raw protocol client over the BLE transport (no ClientSession), used to
/// drive the host with byte-exact sequences (staleness, malformed frames).
class RawBleClient {
  RawBleClient(this.transport, this.connection);

  final MultiplayerTransport transport;
  final TransportConnection connection;
  final MessageCodec codec = const MessageCodec();
  final List<MultiplayerMessage> received = [];
  int _consumed = 0;
  int seq = 0;
  String playerId = '';
  String hostSessionId = '';

  static Future<RawBleClient> connectAndJoin({
    required FakeBleNetwork network,
    required String hostId,
    required String sessionId,
    required String playerName,
  }) async {
    final clientAdapter = FakeBleAdapter(network);
    final transport = BleMultiplayerTransport(adapter: clientAdapter);
    final connection = await transport.connect(
      hostAddress: hostId,
      sessionId: sessionId,
      port: 0,
    );
    final client = RawBleClient(transport, connection);
    final accepted = Completer<JoinAcceptMessage>();
    connection.incoming.listen((raw) {
      try {
        final message = client.codec.decode(raw);
        client.received.add(message);
        if (message is JoinAcceptMessage && !accepted.isCompleted) {
          accepted.complete(message);
        }
      } on Object {
        // Malformed frames are recorded/ignored; the host drops them.
      }
    });
    await connection.send(
      client.codec.encode(
        JoinRequestMessage(
          seq: client.seq++,
          sessionId: sessionId,
          playerName: playerName,
        ),
      ),
    );
    final accept = await accepted.future.timeout(const Duration(seconds: 5));
    client.playerId = accept.playerId;
    client.hostSessionId = accept.sessionId;
    return client;
  }

  Future<T> waitFor<T>({Duration timeout = const Duration(seconds: 5)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (var i = _consumed; i < received.length; i++) {
        final message = received[i];
        if (message is T) {
          _consumed = i + 1;
          return message as T;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException('no message of type $T');
  }

  Future<void> send(MultiplayerMessage message) async {
    await connection.send(codec.encode(message));
  }

  Future<void> close() async {
    await connection.close();
    await transport.dispose();
  }
}

void main() {
  test('a client discovers and joins a Bluetooth-hosted session', () async {
    final network = FakeBleNetwork();
    final sessionId = 'tk-ble-1';
    final hostSetup = await startBleHost(network, sessionId);
    addTearDown(() => hostSetup.host.stop());

    // Client discovery: scan finds the host with its advertised name.
    final clientAdapter = FakeBleAdapter(network);
    final discovery = BleSessionDiscovery(adapter: clientAdapter);
    final discovered = <DiscoveredSession>[];
    discovery.discovered.listen(discovered.add);
    await clientAdapter.startScan();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(discovered, hasLength(1));
    expect(discovered.single.displayName, 'Turtle King Game');
    expect(discovered.single.hostAddress, hostSetup.hostId);
    expect(discovered.single.sessionId, hostSetup.hostId);

    // Client join over the BLE transport (the real ClientSession).
    final client = ClientSession(
      sessionId: discovered.single.sessionId,
      playerName: 'Mia',
      transport: BleMultiplayerTransport(adapter: clientAdapter),
    );
    addTearDown(client.dispose);
    final result = await client.join(
      hostAddress: discovered.single.hostAddress,
      port: 0,
    );
    if (!result.isAccepted) {
      // ignore: avoid_print
      print('JOIN FAILED: ${result.outcome} ${result.reason}');
    }
    expect(result.isAccepted, isTrue);
    expect(result.self!.name, 'Mia');
    expect(hostSetup.host.roster.map((p) => p.name), contains('Mia'));
    expect(hostSetup.host.roster.length, 2);
  });

  test(
    'unrelated BLE advertisers are ignored; only Turtle King hosts surface',
    () async {
      // A nearby smart speaker advertises a different service UUID. The
      // scan is filtered to the Turtle King service at the platform level,
      // but the discovery layer must also reject an advertiser that
      // positively advertises a different service (defense in depth).
      final network = FakeBleNetwork();
      network.registerForeignAdvertiser('speaker-1', 'Kitchen Speaker');
      await startBleHost(network, 'tk-ble-filter');
      final clientAdapter = FakeBleAdapter(network);
      final discovery = BleSessionDiscovery(adapter: clientAdapter);
      final discovered = <DiscoveredSession>[];
      discovery.discovered.listen(discovered.add);
      await clientAdapter.startScan();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(discovered, hasLength(1));
      expect(discovered.single.displayName, 'Turtle King Game');
      expect(discovered.single.hostAddress, isNot('speaker-1'));
    },
  );

  test(
    'a peer with no reported service UUIDs still surfaces (platform quirk)',
    () async {
      // Some platforms omit service UUIDs even on a filtered scan; those
      // peers must NOT be rejected — only peers that positively advertise
      // a different service are dropped.
      final network = FakeBleNetwork();
      final hostSetup = await startBleHost(network, 'tk-ble-nouuid');
      final clientAdapter = FakeBleAdapter(network);
      final discovery = BleSessionDiscovery(adapter: clientAdapter);
      final discovered = <DiscoveredSession>[];
      discovery.discovered.listen(discovered.add);
      await clientAdapter.startScan();
      // Advertiser with an empty service-UUID list (as if the platform
      // failed to report them): still a valid candidate.
      clientAdapter.emitScanResult(
        BleDiscoveredPeer(
          id: 'no-uuid-peer',
          displayName: 'Turtle King game',
          rssi: -60,
          serviceUuids: const {},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        discovered.map((d) => d.hostAddress),
        containsAll([hostSetup.hostId, 'no-uuid-peer']),
      );
    },
  );

  test(
    'a malformed advertisement (blank name) does not crash discovery',
    () async {
      final network = FakeBleNetwork();
      await startBleHost(network, 'tk-ble-malformed');
      final clientAdapter = FakeBleAdapter(network);
      final discovery = BleSessionDiscovery(adapter: clientAdapter);
      final discovered = <DiscoveredSession>[];
      discovery.discovered.listen(discovered.add);
      await clientAdapter.startScan();
      // Blank/whitespace advertisement name: the platform-reported name is
      // unusable; discovery must fall back to the friendly display name
      // rather than surfacing an empty entry or crashing.
      clientAdapter.emitScanResult(
        BleDiscoveredPeer(
          id: 'blank-name-peer',
          displayName: '   ',
          rssi: -55,
          serviceUuids: {kTurtleKingBleServiceUuidString},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(discovered.map((d) => d.hostAddress), contains('blank-name-peer'));
      final blank = discovered.firstWhere(
        (d) => d.hostAddress == 'blank-name-peer',
      );
      expect(blank.displayName, 'Turtle King game');
    },
  );

  test(
    'duplicate advertisements do not create duplicate lobby entries',
    () async {
      // Android re-reports the same device for every advertisement packet;
      // the discovery layer must surface each peer exactly once.
      final network = FakeBleNetwork();
      final hostSetup = await startBleHost(network, 'tk-ble-dup');
      final clientAdapter = FakeBleAdapter(network);
      final discovery = BleSessionDiscovery(adapter: clientAdapter);
      final discovered = <DiscoveredSession>[];
      discovery.discovered.listen(discovered.add);
      await clientAdapter.startScan();
      clientAdapter.emitScanResult(
        BleDiscoveredPeer(
          id: hostSetup.hostId,
          displayName: 'Turtle King Game',
          rssi: -45,
          serviceUuids: {kTurtleKingBleServiceUuidString},
        ),
      );
      clientAdapter.emitScanResult(
        BleDiscoveredPeer(
          id: hostSetup.hostId,
          displayName: 'Turtle King Game',
          rssi: -42,
          serviceUuids: {kTurtleKingBleServiceUuidString},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(discovered, hasLength(1));
    },
  );

  test(
    'scan lifecycle: stop cancels the scan, a later access restarts it',
    () async {
      final network = FakeBleNetwork();
      final hostSetup = await startBleHost(network, 'tk-ble-lifecycle');
      final clientAdapter = FakeBleAdapter(network);
      final discovery = BleSessionDiscovery(adapter: clientAdapter);
      final first = <DiscoveredSession>[];
      discovery.discovered.listen(first.add);
      await clientAdapter.startScan();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(first, hasLength(1));

      await discovery.stop();
      expect(clientAdapter.isScanning, isFalse);

      // A fresh "Search again" creates a new scan cycle and re-surfaces the
      // host (the dedupe set is per-cycle).
      final second = <DiscoveredSession>[];
      discovery.discovered.listen(second.add);
      await clientAdapter.startScan();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(second, hasLength(1));
      expect(second.single.hostAddress, hostSetup.hostId);
    },
  );

  test(
    'the host adopts the real session id; the client joins by any locator',
    () async {
      // A BLE joiner does not know the host's session id (advertisements carry
      // no structured payload), so it joins with a placeholder — exactly like
      // a manual-IP LAN join. The host's JOIN_ACCEPT carries the real id.
      final network = FakeBleNetwork();
      final sessionId = 'tk-ble-2';
      final hostSetup = await startBleHost(network, sessionId);
      addTearDown(() => hostSetup.host.stop());

      final client = ClientSession(
        sessionId: 'ble-placeholder',
        playerName: 'Mia',
        transport: BleMultiplayerTransport(adapter: FakeBleAdapter(network)),
      );
      addTearDown(client.dispose);
      final result = await client.join(hostAddress: hostSetup.hostId, port: 0);
      expect(result.isAccepted, isTrue);
      expect(hostSetup.host.roster.map((p) => p.name), contains('Mia'));
    },
  );

  test(
    'a full game plays over the BLE transport with private-card isolation',
    () async {
      final network = FakeBleNetwork();
      final sessionId = 'tk-ble-game';
      final hostSetup = await startBleHost(network, sessionId);
      addTearDown(() => hostSetup.host.stop());

      final client = ClientSession(
        sessionId: sessionId,
        playerName: 'Mia',
        transport: BleMultiplayerTransport(adapter: FakeBleAdapter(network)),
      );
      addTearDown(client.dispose);
      final result = await client.join(hostAddress: hostSetup.hostId, port: 0);
      expect(result.isAccepted, isTrue);

      // Subscribe BEFORE startGame: the host's GAME_START/STATE/PRIVATE
      // sends are unawaited microtasks that can land while `await startGame`
      // yields, and a broadcast stream drops events nobody is listening to.
      final gameEvents = <ClientGameplayEvent>[];
      final gameSub = client.gameplayEvents.listen(gameEvents.add);
      addTearDown(gameSub.cancel);

      // Host builds the authoritative game from the roster and starts it.
      final players = [
        for (final p in hostSetup.host.roster)
          Player(id: p.id, name: p.name, color: Color(p.color)),
      ];
      final game = GameState(players: players, random: Random(7));
      await hostSetup.host.startGame(game);

      ClientGameplayEvent gameStarted() => gameEvents.firstWhere(
        (e) => e.type == ClientGameplayEventType.gameStarted,
      );
      await pumpUntil(
        () => gameEvents.any(
          (e) => e.type == ClientGameplayEventType.gameStarted,
        ),
        timeout: kSlow,
      );
      expect(gameStarted().publicState, isNotNull);

      await pumpUntil(
        () => gameEvents.any(
          (e) => e.type == ClientGameplayEventType.privateUpdated,
        ),
        timeout: kSlow,
      );
      final private = gameEvents.firstWhere(
        (e) => e.type == ClientGameplayEventType.privateUpdated,
      );
      expect(private.privateState!.recipientPlayerId, client.self!.id);
      // Public state carries no card/rank/suit/hand/deck data.
      final publicJson = jsonDecode(
        const JsonEncoder().convert(gameStarted().publicState!.toJson()),
      );
      expectNoForbiddenKeys(publicJson, [
        'card',
        'rank',
        'suit',
        'hand',
        'deck',
      ]);
      // The private card is the recipient's own visible card.
      expect(private.privateState!.card, isNotNull);

      // Actions route through the host and come back with the new state.
      client.requestAction(GameAction.revealCurrentPlayer);
      await pumpUntil(
        () => gameEvents.any(
          (e) => e.type == ClientGameplayEventType.stateUpdated,
        ),
        timeout: kSlow,
      );
      final updated = gameEvents.firstWhere(
        (e) => e.type == ClientGameplayEventType.stateUpdated,
      );
      expect(updated.publicState, isNotNull);
    },
  );

  test('the client RemoteDriver emits a rebuild event after an accepted action '
      '(regression: gameplay screen never re-rendered on device)', () async {
    // Physical defect: after a connected Bluetooth client's first Reveal,
    // the game state advanced on both devices (the host applied the action
    // and broadcast the new state) but the client's gameplay screen stayed
    // frozen. Root cause: RemoteDriver updated its internal view on
    // stateUpdated/privateUpdated but emitted no RemoteGameEvent, and
    // RemoteGameScreen only rebuilds on those events. This test pins the
    // contract: every accepted action that updates the view must emit.
    final network = FakeBleNetwork();
    final sessionId = 'tk-ble-rebuild';
    final hostSetup = await startBleHost(network, sessionId);
    addTearDown(() => hostSetup.host.stop());

    final clientAdapter = FakeBleAdapter(network);
    final client = ClientSession(
      sessionId: sessionId,
      playerName: 'Mia',
      transport: BleMultiplayerTransport(adapter: clientAdapter),
    );
    addTearDown(client.dispose);
    final result = await client.join(hostAddress: hostSetup.hostId, port: 0);
    expect(result.isAccepted, isTrue);

    final driver = RemoteDriver(
      sessionId: sessionId,
      playerName: 'Mia',
      rejoinTransport: BleMultiplayerTransport(adapter: clientAdapter),
      rejoinHostAddress: hostSetup.hostId,
    );
    addTearDown(driver.dispose);
    driver.attach(client);
    final emitted = <RemoteGameEvent>[];
    final eventSub = driver.events.listen(emitted.add);
    addTearDown(eventSub.cancel);

    // Host starts the authoritative game built from the joined roster.
    final players = [
      for (final p in hostSetup.host.roster)
        Player(id: p.id, name: p.name, color: Color(p.color)),
    ];
    final game = GameState(players: players, random: Random(7));
    await hostSetup.host.startGame(game);
    await pumpUntil(
      () => emitted.any((e) => e.status == RemoteGameStatus.playing),
      timeout: kSlow,
    );

    // The host is Player 0 and views first: reveal and pass so the client
    // (Player 1) becomes the current viewer and may legally act.
    game.revealCurrentPlayer();
    hostSetup.host.broadcastHostAction();
    game.passToNextPlayer();
    hostSetup.host.broadcastHostAction();
    await pumpUntil(() => driver.view.isMyTurn, timeout: kSlow);

    // The client performs its first Reveal. The host must accept it,
    // broadcast the new state, and the driver must notify the UI so the
    // screen re-renders.
    final before = emitted.length;
    client.requestAction(GameAction.revealCurrentPlayer);
    await pumpUntil(() => driver.view.currentPlayerRevealed, timeout: kSlow);
    // The state reached the client's view...
    expect(driver.view.currentPlayerRevealed, isTrue);
    // ...and an event was emitted to trigger the screen rebuild (the
    // regression: no event, so the UI froze even though the game moved on).
    expect(emitted.length, greaterThan(before));
  });

  test('a client leaving removes it from the host roster', () async {
    final network = FakeBleNetwork();
    final sessionId = 'tk-ble-leave';
    final hostSetup = await startBleHost(network, sessionId);
    addTearDown(() => hostSetup.host.stop());

    final client = ClientSession(
      sessionId: sessionId,
      playerName: 'Mia',
      transport: BleMultiplayerTransport(adapter: FakeBleAdapter(network)),
    );
    final result = await client.join(hostAddress: hostSetup.hostId, port: 0);
    expect(result.isAccepted, isTrue);
    expect(hostSetup.host.roster.length, 2);

    await client.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(hostSetup.host.roster.length, 1);
    expect(hostSetup.host.roster.single.id, kHostPlayerId);
  });

  test('host loss is detected by the client (no graceful close)', () async {
    final network = FakeBleNetwork();
    final sessionId = 'tk-ble-hostloss';
    final hostSetup = await startBleHost(network, sessionId);

    final client = ClientSession(
      sessionId: sessionId,
      playerName: 'Mia',
      transport: BleMultiplayerTransport(adapter: FakeBleAdapter(network)),
    );
    addTearDown(client.dispose);
    final result = await client.join(hostAddress: hostSetup.hostId, port: 0);
    expect(result.isAccepted, isTrue);

    final lost = Completer<void>();
    client.events.listen((event) {
      if (event.type == ClientSessionEventType.connectionLost &&
          !lost.isCompleted) {
        lost.complete();
      }
    });

    // The host vanishes abruptly (app killed / out of range): no close
    // frame reaches the client.
    network.simulateHostLoss(hostSetup.hostId);
    await lost.future.timeout(const Duration(seconds: 5));
  });

  test('a reconnecting client is re-admitted even when the host missed the '
      'disconnect event (real-device mid-game reconnect failure)', () async {
    // Real device: the joiner's link drops but the host's peripheral never
    // delivers BleHostDisconnected (Android can miss it), so the host's
    // BleTransportServer._byPeer keeps the stale connection. When the
    // client reconnects, _admit must REPLACE the stale entry — otherwise
    // the new connection is never surfaced to the session layer and the
    // rejoin JOIN_REQUEST is silently dropped (observed on physical
    // phones: GATT reconnect succeeds, then "Connection failed").
    final network = FakeBleNetwork();
    final sessionId = 'tk-ble-stale-admit';
    final hostSetup = await startBleHost(network, sessionId);
    addTearDown(() => hostSetup.host.stop());

    final clientAdapter = FakeBleAdapter(network);
    final client = ClientSession(
      sessionId: sessionId,
      playerName: 'Mia',
      transport: BleMultiplayerTransport(adapter: clientAdapter),
    );
    addTearDown(client.dispose);
    final result = await client.join(hostAddress: hostSetup.hostId, port: 0);
    expect(result.isAccepted, isTrue);
    final firstId = result.self!.id;
    expect(hostSetup.host.roster.length, 2);

    final driver = RemoteDriver(
      sessionId: sessionId,
      playerName: 'Mia',
      rejoinTransport: BleMultiplayerTransport(adapter: clientAdapter),
      rejoinHostAddress: hostSetup.hostId,
    );
    addTearDown(driver.dispose);
    driver.attach(client);

    // The client link drops silently: the client's own disconnect stream
    // fires, but the host is never told (no BleHostDisconnected), so its
    // _byPeer entry survives.
    final clientId = clientAdapter.lastClientLinkId;
    expect(clientId, isNotNull);
    network.simulateClientLinkSilentDrop(clientId!);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final rejoined = await driver.reconnect();
    expect(rejoined, isTrue);
    // Identity reclaimed: same player id, no duplicate roster entry.
    final reclaimed = hostSetup.host.roster.where((p) => p.name == 'Mia');
    expect(reclaimed, hasLength(1));
    expect(reclaimed.single.id, firstId);
  });

  test(
    'a client can reconnect and reclaim its identity after a drop',
    () async {
      final network = FakeBleNetwork();
      final sessionId = 'tk-ble-reconnect';
      final hostSetup = await startBleHost(network, sessionId);
      addTearDown(() => hostSetup.host.stop());

      // RemoteDriver tracks the rejoin transport + peer id so a reconnect
      // uses the same BLE link (port 0 is fine — the fix under test).
      final clientAdapter = FakeBleAdapter(network);
      final client = ClientSession(
        sessionId: sessionId,
        playerName: 'Mia',
        transport: BleMultiplayerTransport(adapter: clientAdapter),
      );
      addTearDown(client.dispose);
      final result = await client.join(hostAddress: hostSetup.hostId, port: 0);
      expect(result.isAccepted, isTrue);
      final firstId = result.self!.id;

      final driver = RemoteDriver(
        sessionId: sessionId,
        playerName: 'Mia',
        rejoinTransport: BleMultiplayerTransport(adapter: clientAdapter),
        rejoinHostAddress: hostSetup.hostId,
      );
      addTearDown(driver.dispose);
      driver.attach(client);

      // Drop the link and let the driver reconnect to the same host.
      network.simulateHostLoss(hostSetup.hostId);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final rejoined = await driver.reconnect();
      expect(rejoined, isTrue);
      // The host reclaimed the original identity: same player id, no duplicate.
      final reclaimed = hostSetup.host.roster.where((p) => p.name == 'Mia');
      expect(reclaimed, hasLength(1));
      expect(reclaimed.single.id, firstId);
    },
  );

  test(
    'a join that times out fails with a typed failure, not a crash',
    () async {
      final network = FakeBleNetwork();
      final sessionId = 'tk-ble-timeout';
      final hostSetup = await startBleHost(network, sessionId);
      addTearDown(() => hostSetup.host.stop());

      final clientAdapter = FakeBleAdapter(network);
      clientAdapter.connectGate = Completer<void>();
      final client = ClientSession(
        sessionId: sessionId,
        playerName: 'Mia',
        transport: BleMultiplayerTransport(adapter: clientAdapter),
      );
      addTearDown(client.dispose);
      final result = await client.join(
        hostAddress: hostSetup.hostId,
        port: 0,
        connectTimeout: const Duration(milliseconds: 200),
      );
      expect(result.isAccepted, isFalse);
      expect(
        result.outcome,
        anyOf(JoinOutcome.connectionFailed, JoinOutcome.timedOut),
      );
    },
  );

  test('a connect that never completes (silent platform failure) still times '
      'out instead of hanging', () async {
    final network = FakeBleNetwork();
    final sessionId = 'tk-ble-hang';
    final hostSetup = await startBleHost(network, sessionId);
    addTearDown(() => hostSetup.host.stop());

    final clientAdapter = FakeBleAdapter(network);
    // Simulate Android connectGatt failing silently: no completion, no
    // error, no callback. The transport must still bound the wait.
    clientAdapter.hangConnect = true;
    final client = ClientSession(
      sessionId: sessionId,
      playerName: 'Mia',
      transport: BleMultiplayerTransport(adapter: clientAdapter),
    );
    addTearDown(client.dispose);
    final started = DateTime.now();
    final result = await client.join(
      hostAddress: hostSetup.hostId,
      port: 0,
      connectTimeout: const Duration(milliseconds: 300),
    );
    final elapsed = DateTime.now().difference(started);
    expect(result.isAccepted, isFalse);
    expect(
      result.outcome,
      anyOf(JoinOutcome.connectionFailed, JoinOutcome.timedOut),
    );
    // Bounded by the connect timeout — the join must not hang forever.
    expect(elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('duplicate join attempts on one client are blocked', () async {
    final network = FakeBleNetwork();
    final sessionId = 'tk-ble-dup';
    final hostSetup = await startBleHost(network, sessionId);
    addTearDown(() => hostSetup.host.stop());

    final clientAdapter = FakeBleAdapter(network);
    clientAdapter.connectGate = Completer<void>();
    final client = ClientSession(
      sessionId: sessionId,
      playerName: 'Mia',
      transport: BleMultiplayerTransport(adapter: clientAdapter),
    );
    addTearDown(client.dispose);

    final first = client.join(hostAddress: hostSetup.hostId, port: 0);
    // A second join while the first is in flight is a programming error.
    expect(
      () => client.join(hostAddress: hostSetup.hostId, port: 0),
      throwsStateError,
    );
    clientAdapter.connectGate!.complete();
    final result = await first;
    expect(result.isAccepted, isTrue);
  });

  test(
    'malformed frames and protocol garbage close the offending peer',
    () async {
      final network = FakeBleNetwork();
      final sessionId = 'tk-ble-mal';
      final hostSetup = await startBleHost(network, sessionId);
      addTearDown(() => hostSetup.host.stop());

      // A raw client whose link we drive directly (bypasses the transport
      // encoder so we can send byte-level garbage).
      final clientAdapter = FakeBleAdapter(network);
      final transport = BleMultiplayerTransport(adapter: clientAdapter);
      final link = await clientAdapter.connect(hostSetup.hostId);
      addTearDown(() => transport.dispose());

      // Track the host-side connection closing (dropped by the server).
      final closed = Completer<void>();
      hostSetup.hostAdapter.hostEvents.listen((event) {
        if (event is BleHostDisconnected && !closed.isCompleted) {
          closed.complete();
        }
      });

      // 1) Invalid framing header: assembler throws, peer is dropped.
      await link.send(Uint8List.fromList([0x7f, 0, 0, 0, 1, 1]));
      await closed.future.timeout(const Duration(seconds: 5));

      // 2) A second peer sending valid framing but non-protocol garbage is
      // closed by the session layer (codec rejects it).
      final link2 = await clientAdapter.connect(hostSetup.hostId);
      final closed2 = Completer<void>();
      hostSetup.hostAdapter.hostEvents.listen((event) {
        if (event is BleHostDisconnected && !closed2.isCompleted) {
          closed2.complete();
        }
      });
      for (final chunk in encodeBleString(
        'this is not turtle king json',
        180,
      )) {
        await link2.send(chunk);
      }
      await closed2.future.timeout(const Duration(seconds: 5));
    },
  );

  test(
    'stale and non-owned actions are rejected by the host over BLE',
    () async {
      final network = FakeBleNetwork();
      final sessionId = 'tk-ble-stale';
      final hostSetup = await startBleHost(network, sessionId);
      addTearDown(() => hostSetup.host.stop());

      final client = await RawBleClient.connectAndJoin(
        network: network,
        hostId: hostSetup.hostId,
        sessionId: sessionId,
        playerName: 'Mia',
      );
      addTearDown(client.close);
      expect(hostSetup.host.roster.length, 2);

      // The host only validates actions while a game is running.
      final players = [
        for (final p in hostSetup.host.roster)
          Player(id: p.id, name: p.name, color: Color(p.color)),
      ];
      await hostSetup.host.startGame(
        GameState(players: players, random: Random(11)),
      );

      // An action from a player who does not own the turn is rejected.
      await client.send(
        ActionRequestMessage(
          seq: client.seq++,
          sessionId: client.hostSessionId,
          action: GameAction.revealCurrentPlayer,
          playerId: client.playerId,
        ),
      );
      final first = await client.waitFor<ActionRejectedMessage>();
      expect(first.reason, 'not your turn');

      // Re-sending the same seq is rejected as stale/duplicate.
      await client.send(
        ActionRequestMessage(
          seq: client.seq - 1,
          sessionId: client.hostSessionId,
          action: GameAction.revealCurrentPlayer,
          playerId: client.playerId,
        ),
      );
      final stale = await client.waitFor<ActionRejectedMessage>();
      expect(stale.reason, contains('stale or duplicate'));
    },
  );

  test('two clients can join the same Bluetooth host', () async {
    final network = FakeBleNetwork();
    final sessionId = 'tk-ble-multi';
    final hostSetup = await startBleHost(network, sessionId);
    addTearDown(() => hostSetup.host.stop());

    final mia = ClientSession(
      sessionId: sessionId,
      playerName: 'Mia',
      transport: BleMultiplayerTransport(adapter: FakeBleAdapter(network)),
    );
    addTearDown(mia.dispose);
    final r1 = await mia.join(hostAddress: hostSetup.hostId, port: 0);
    expect(r1.isAccepted, isTrue);

    final leo = ClientSession(
      sessionId: sessionId,
      playerName: 'Leo',
      transport: BleMultiplayerTransport(adapter: FakeBleAdapter(network)),
    );
    addTearDown(leo.dispose);
    final r2 = await leo.join(hostAddress: hostSetup.hostId, port: 0);
    expect(r2.isAccepted, isTrue);

    expect(hostSetup.host.roster.length, 3);
    expect(
      hostSetup.host.roster.map((p) => p.name),
      containsAll(['Mia', 'Leo']),
    );
  });

  test(
    'BLE discovery carries no structured session payload (privacy)',
    () async {
      final network = FakeBleNetwork();
      await startBleHost(network, 'tk-ble-priv');
      final clientAdapter = FakeBleAdapter(network);
      final discovery = BleSessionDiscovery(adapter: clientAdapter);
      final peers = <BleDiscoveredPeer>[];
      discovery.discovered.listen(
        (s) => peers.add(
          BleDiscoveredPeer(
            id: s.sessionId,
            displayName: s.displayName,
            rssi: 0,
          ),
        ),
      );
      await clientAdapter.startScan();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(peers, hasLength(1));
      // The advertised identity is a locator: session id and join code are
      // not discoverable from the advertisement alone.
      expect(peers.single.id, isNot('tk-ble-priv'));
    },
  );
}
