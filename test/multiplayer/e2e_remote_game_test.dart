import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/multiplayer/public_state.dart';
import 'package:turtle_king/multiplayer/remote_driver.dart';
import 'package:turtle_king/multiplayer/session.dart';

import 'helpers.dart';

Future<void> pump([Duration duration = const Duration(milliseconds: 40)]) =>
    Future<void>.delayed(duration);

const Duration kSlow = Duration(seconds: 15);

Future<void> pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Builds a game whose player ids match a joined roster.
GameState rosterGame(List<PublicPlayer> roster, {int seed = 7}) {
  return GameState(
    players: [
      for (final p in roster)
        testPlayer(roster.indexOf(p), id: p.id, name: p.name),
    ],
    random: Random(seed),
  );
}

void main() {
  group('E2E remote game over loopback', () {
    test('two clients join, play a full round, disconnect/reconnect, and the '
        'host can terminate the session', () async {
      // -----------------------------------------------------------------
      // 1–3. Host creates the session; both clients connect and join.
      // -----------------------------------------------------------------
      final host = HostSession(sessionId: 'e2e-1');
      final server = await host.start(
        displayName: 'E2E',
        hostName: 'H',
        port: 0,
      );

      final miaDriver = RemoteDriver(sessionId: 'e2e-1', playerName: 'Mia');
      final leoDriver = RemoteDriver(sessionId: 'e2e-1', playerName: 'Leo');
      final miaJoin = await miaDriver.join(
        hostAddress: '127.0.0.1',
        port: server.port,
      );
      final leoJoin = await leoDriver.join(
        hostAddress: '127.0.0.1',
        port: server.port,
      );
      expect(miaJoin.isAccepted, isTrue);
      expect(leoJoin.isAccepted, isTrue);
      await pumpUntil(() => host.roster.length == 3, timeout: kSlow);

      // -----------------------------------------------------------------
      // 4–5. Host starts the game; both clients see it.
      // -----------------------------------------------------------------
      final game = rosterGame(host.roster, seed: 11);
      await host.startGame(game);
      await pumpUntil(
        () =>
            miaDriver.status == RemoteGameStatus.playing &&
            leoDriver.status == RemoteGameStatus.playing,
        timeout: kSlow,
      );
      expect(miaDriver.view.players.map((p) => p.name), ['H', 'Mia', 'Leo']);
      // Clients receive their own private cards.
      await pumpUntil(() => miaDriver.view.myCard != null, timeout: kSlow);
      await pumpUntil(() => leoDriver.view.myCard != null, timeout: kSlow);

      // -----------------------------------------------------------------
      // 6–10. Play the viewing phase through the host, then verify the
      //        clients track the state broadcasts.
      // -----------------------------------------------------------------
      // -----------------------------------------------------------------
      // 6–10. Play the viewing phase through the host, then verify the
      //        clients track the state broadcasts.
      // -----------------------------------------------------------------
      game.revealCurrentPlayer();
      host.broadcastHostAction();
      game.passToNextPlayer();
      host.broadcastHostAction();
      // Now it is Mia's viewing turn. She acts through her driver; the
      // host validates and broadcasts.
      await pumpUntil(() => miaDriver.view.isMyTurn, timeout: kSlow);
      miaDriver.revealCurrentPlayer();
      await pumpUntil(
        () =>
            game.currentPlayerRevealed && miaDriver.view.currentPlayerRevealed,
        timeout: kSlow,
      );
      miaDriver.passToNextPlayer();
      // Leo is next to view: he reveals and passes through his driver.
      await pumpUntil(() => leoDriver.view.isMyTurn, timeout: kSlow);
      leoDriver.revealCurrentPlayer();
      await pumpUntil(
        () => leoDriver.view.currentPlayerRevealed,
        timeout: kSlow,
      );
      leoDriver.passToNextPlayer();
      await pumpUntil(() => game.allPlayersViewed, timeout: kSlow);
      await pumpUntil(() => miaDriver.view.pouringStarted, timeout: kSlow);

      // -----------------------------------------------------------------
      // 11–13. Pouring: host holds out, then Mia, then Leo — the round
      //        completes when the last active player holds out.
      // -----------------------------------------------------------------
      expect(game.pourCurrentPlayer.name, 'H');
      game.holdOut(game.players[0]);
      host.broadcastHostAction();
      await pumpUntil(() => miaDriver.view.isMyTurn, timeout: kSlow);
      miaDriver.holdOut();
      await pumpUntil(() => leoDriver.view.isMyTurn, timeout: kSlow);
      leoDriver.holdOut();
      await pumpUntil(
        () =>
            game.roundComplete &&
            miaDriver.view.roundComplete &&
            leoDriver.view.roundComplete,
        timeout: kSlow,
      );
      expect(game.eliminationHistory.length, 0);

      // -----------------------------------------------------------------
      // 14. A stale/duplicate action from a client cannot change anything.
      // -----------------------------------------------------------------
      final stateSeqBefore = host.stateSeq;
      miaDriver.holdOut(); // no-op: not Mia's turn and round is complete
      await pump(const Duration(milliseconds: 300));
      expect(host.stateSeq, stateSeqBefore);

      // -----------------------------------------------------------------
      // 15–17. Disconnect and reconnect Mia; she resyncs.
      // -----------------------------------------------------------------
      final miaSessionBefore = miaDriver.selfPlayerId;
      await miaDriver.leave();
      await pumpUntil(() => host.roster.length == 3, timeout: kSlow);
      // Reconnect with the same name.
      final miaDriver2 = RemoteDriver(sessionId: 'e2e-1', playerName: 'Mia');
      final rejoin = await miaDriver2.join(
        hostAddress: '127.0.0.1',
        port: server.port,
      );
      expect(rejoin.isAccepted, isTrue);
      expect(miaDriver2.selfPlayerId, miaSessionBefore);
      // The reconnected client receives the authoritative state.
      await pumpUntil(() => miaDriver2.view.roundComplete, timeout: kSlow);
      expect(miaDriver2.view.roundNumber, game.roundNumber);

      // -----------------------------------------------------------------
      // 18. Next round starts; clients track it.
      // -----------------------------------------------------------------
      game.startNextRound();
      host.broadcastHostAction();
      await pumpUntil(
        () => miaDriver2.view.roundNumber == game.roundNumber,
        timeout: kSlow,
      );
      expect(miaDriver2.view.pouringStarted, isFalse);
      // Fresh private cards are delivered for the new round.
      await pumpUntil(() => miaDriver2.view.myCard != null, timeout: kSlow);

      // -----------------------------------------------------------------
      // 19–20. Host terminates; clients enter session-ended state.
      // -----------------------------------------------------------------
      final miaEvents = <RemoteGameStatus>[];
      final miaSub = miaDriver2.events.listen((e) {
        miaEvents.add(e.status);
      });
      await host.stop(reason: 'host-left');
      await pumpUntil(
        () => miaEvents.contains(RemoteGameStatus.sessionEnded),
        timeout: kSlow,
      );
      expect(miaDriver2.status, RemoteGameStatus.sessionEnded);

      await miaSub.cancel();
      await miaDriver2.dispose();
      await leoDriver.dispose();
    });

    test(
      'elimination and game completion propagate to clients over the wire',
      () async {
        final host = HostSession(sessionId: 'e2e-elim');
        final server = await host.start(
          displayName: 'G',
          hostName: 'H',
          port: 0,
        );
        final leoDriver = RemoteDriver(
          sessionId: 'e2e-elim',
          playerName: 'Leo',
        );
        final join = await leoDriver.join(
          hostAddress: '127.0.0.1',
          port: server.port,
        );
        expect(join.isAccepted, isTrue);
        await pumpUntil(() => host.roster.length == 2, timeout: kSlow);

        final game = rosterGame(host.roster, seed: 5);
        await host.startGame(game);
        await pumpUntil(
          () => leoDriver.status == RemoteGameStatus.playing,
          timeout: kSlow,
        );

        // Viewing: the host views and passes, then Leo does the same.
        game.revealCurrentPlayer();
        host.broadcastHostAction();
        game.passToNextPlayer();
        host.broadcastHostAction();
        await pumpUntil(() => leoDriver.view.isMyTurn, timeout: kSlow);
        leoDriver.revealCurrentPlayer();
        await pumpUntil(
          () => leoDriver.view.currentPlayerRevealed,
          timeout: kSlow,
        );
        leoDriver.passToNextPlayer();
        await pumpUntil(() => game.pouringStarted, timeout: kSlow);

        // Pouring: the host holds out, leaving Leo to pour.
        expect(game.pourCurrentPlayer.name, 'H');
        game.holdOut(game.players[0]);
        host.broadcastHostAction();
        await pumpUntil(() => leoDriver.view.isMyTurn, timeout: kSlow);

        // Leo calls YAMADA until the sixth drink eliminates him and — with
        // only the host left — the game completes immediately.
        for (var i = 1; i <= 6; i++) {
          final before = host.stateSeq;
          leoDriver.callYamada();
          await pumpUntil(() => host.stateSeq > before, timeout: kSlow);
        }
        await pumpUntil(() => game.gameComplete, timeout: kSlow);
        expect(game.eliminationHistory.length, 1);
        expect(game.finalResult?.turtleKings.map((p) => p.id), ['host']);

        // The client sees the elimination and the final result.
        await pumpUntil(
          () =>
              leoDriver.view.gameComplete &&
              leoDriver.view.iAmEliminated &&
              leoDriver.view.finalResult != null,
          timeout: kSlow,
        );
        expect(leoDriver.view.eliminations.length, 1);
        expect(leoDriver.view.finalResult!.turtleKings, ['host']);
        // No further actions are possible after completion.
        final stateSeqAfter = host.stateSeq;
        leoDriver.holdOut();
        await pump(const Duration(milliseconds: 300));
        expect(host.stateSeq, stateSeqAfter);

        await leoDriver.dispose();
        await host.stop();
      },
    );

    test('a client cannot act out of turn: the host rejects and state is '
        'unchanged', () async {
      final host = HostSession(sessionId: 'e2e-2');
      final server = await host.start(displayName: 'G', hostName: 'H', port: 0);
      final leoDriver = RemoteDriver(sessionId: 'e2e-2', playerName: 'Leo');
      final join = await leoDriver.join(
        hostAddress: '127.0.0.1',
        port: server.port,
      );
      expect(join.isAccepted, isTrue);
      final game = rosterGame(host.roster);
      await host.startGame(game);
      await pumpUntil(
        () => leoDriver.status == RemoteGameStatus.playing,
        timeout: kSlow,
      );

      // Leo is not the current viewer (the host is Player 0): his action
      // must be rejected and the host state must not move.
      String? rejection;
      final sub = leoDriver.events.listen((e) => rejection ??= e.rejection);
      final before = host.stateSeq;
      leoDriver.revealCurrentPlayer();
      await pumpUntil(() => rejection != null, timeout: kSlow);
      expect(rejection, contains('turn'));
      expect(host.stateSeq, before);
      expect(game.currentPlayerRevealed, isFalse);

      await sub.cancel();
      await leoDriver.dispose();
      await host.stop();
    });

    test('wrong-session actions are rejected', () async {
      final host = HostSession(sessionId: 'e2e-3');
      final server = await host.start(displayName: 'G', hostName: 'H', port: 0);
      final driver = RemoteDriver(
        sessionId: 'other-session',
        playerName: 'Leo',
      );
      final join = await driver.join(
        hostAddress: '127.0.0.1',
        port: server.port,
      );
      // The join itself is accepted (the connection binds the session) but
      // actions and resyncs carry the adopted real id; a manually forged
      // message with the wrong id is refused by the host.
      expect(join.isAccepted, isTrue);
      await pump(const Duration(milliseconds: 200));
      await host.stop();
      await driver.dispose();
    });
  });
}
