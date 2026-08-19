import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:turtle_king/multiplayer/discovery.dart';
import 'package:turtle_king/multiplayer/host_lobby_screen.dart';
import 'package:turtle_king/multiplayer/join_lobby_screen.dart';
import 'package:turtle_king/multiplayer/join_payload.dart';
import 'package:turtle_king/multiplayer/relay_server.dart';
import 'package:turtle_king/multiplayer/relay_transport.dart';
import 'package:turtle_king/multiplayer/session.dart';

/// Lets real socket I/O progress inside a widget test (flutter_test runs
/// tests in a fake-async zone where real network futures need a runAsync
/// window to complete).
Future<void> realWait(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 250),
]) {
  return tester.runAsync(() => Future<void>.delayed(duration));
}

void main() {
  group('host lobby join UX', () {
    testWidgets('shows the 6-digit code, the QR code, and a copy action', (
      tester,
    ) async {
      // Clipboard writes go through the platform channel; mock it so the
      // copy action completes deterministically in the test.
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      // The host lobby connects to the internet relay over a real WebSocket:
      // run an in-process relay on loopback for the test.
      final relay = RelayServer();
      await tester.runAsync(() => relay.start(port: 0));
      addTearDown(() => tester.runAsync(() => relay.stop()));
      final relayUrl = 'ws://127.0.0.1:${relay.port}';
      await tester.pumpWidget(
        MaterialApp(
          home: HostLobbyScreen(
            joinCodeGenerator: () => '483729',
            relayUrl: relayUrl,
          ),
        ),
      );

      await tester.tap(find.text('Start Session'));
      // The host lobby performs a real WebSocket handshake with the relay:
      // alternate real-async windows and pumped frames until the hosting
      // view appears.
      for (
        var i = 0;
        i < 12 && find.text('Join Game').evaluate().isEmpty;
        i++
      ) {
        await realWait(tester);
        await tester.pumpAndSettle();
      }

      expect(find.text('Join Game'), findsOneWidget);
      expect(find.text('483 729'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Copy code'), findsOneWidget);

      // The QR is rendered with an accessible label (its payload identifies
      // the session on the relay — see [JoinPayload]).
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.semanticsLabel, contains('Join QR code'));

      await tester.tap(find.text('Copy code'));
      await tester.pump();
      expect(find.text('Code copied'), findsOneWidget);
      // Flush the 2s “Code copied” reset timer before the test ends.
      await tester.pump(const Duration(seconds: 3));

      // Clean shutdown: end the session and return to the form. The stop
      // chain is real socket I/O driven through the fake-async zone, so
      // alternate real-wait windows and pumped frames until it lands.
      final endSession = find.text('End Session');
      await tester.scrollUntilVisible(
        endSession,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(endSession);
      for (
        var i = 0;
        i < 12 && find.text('Start Session').evaluate().isEmpty;
        i++
      ) {
        await realWait(tester);
        await tester.pumpAndSettle();
      }
      expect(find.text('Start Session'), findsOneWidget);

      // The session stop chain ends with a real WebSocket close, and Dart's
      // WebSocket.close() schedules a 5s close-handshake timeout timer.
      // Under full-suite load the peer's close ack can arrive after the
      // test body ends, leaving that timer pending ("A Timer is still
      // pending"). Advancing fake time past the timeout fires it
      // deterministically instead of racing the ack.
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets(
      'an empty relay configuration shows a clear, placeholder-free error',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: HostLobbyScreen(relayUrl: '')),
        );

        await tester.tap(find.text('Start Session'));
        await tester.pump();

        expect(
          find.textContaining('Multiplayer relay is not configured'),
          findsOneWidget,
        );
        // A placeholder endpoint must never appear in a user-facing message.
        expect(find.textContaining('wss://'), findsNothing);
        expect(find.textContaining('your-relay'), findsNothing);
        expect(find.textContaining('example.com'), findsNothing);
      },
    );
  });

  group('join lobby join UX', () {
    testWidgets('scan + code are the primary options; manual IP is collapsed', (
      tester,
    ) async {
      await tester.pumpWidget(MaterialApp(home: JoinLobbyScreen()));

      expect(find.text('Scan QR Code'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Join code'), findsOneWidget);
      // LAN discovery + manual host IP live behind the collapsed "For Nerds"
      // section and are off by default — normal play is QR/code over the
      // internet relay. The old "Developer options" label is gone.
      expect(find.text('For Nerds'), findsOneWidget);
      expect(find.text('Developer options'), findsNothing);
      expect(find.text('Developer'), findsNothing);
      // The friendly subtitle is part of the collapsed tile itself.
      expect(
        find.text('Advanced options for curious turtles.'),
        findsOneWidget,
      );
      // The advanced content is collapsed by default.
      expect(find.text('Manual setup (host IP)'), findsNothing);
      expect(find.widgetWithText(TextField, 'Host IPv4'), findsNothing);
      // Expanding "For Nerds" keeps the subtitle and reveals the options.
      await tester.tap(find.text('For Nerds'));
      await tester.pumpAndSettle();
      expect(
        find.text('Advanced options for curious turtles.'),
        findsOneWidget,
      );
      // The Bluetooth section above "For Nerds" made the lobby taller;
      // scroll the debug tile into view before tapping it.
      await tester.ensureVisible(find.text('Manual setup (host IP)'));
      await tester.tap(find.text('Manual setup (host IP)'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Host IPv4'), findsOneWidget);
    });

    testWidgets('an invalid QR payload is rejected safely', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: JoinLobbyScreen(
            scanPayloadProvider: () async => 'not-a-turtle-king-payload',
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Your name'),
        'Mia',
      );
      await tester.tap(find.text('Scan QR Code'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid QR code'), findsOneWidget);
    });

    testWidgets('cancelling the scanner leaves the lobby untouched', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: JoinLobbyScreen(scanPayloadProvider: () async => null),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Your name'),
        'Mia',
      );
      await tester.tap(find.text('Scan QR Code'));
      await tester.pumpAndSettle();

      expect(find.text('Scan QR Code'), findsOneWidget);
      expect(find.textContaining('Invalid'), findsNothing);
    });

    testWidgets('an invalid join code is rejected safely', (tester) async {
      await tester.pumpWidget(MaterialApp(home: JoinLobbyScreen()));
      await tester.enterText(
        find.widgetWithText(TextField, 'Your name'),
        'Mia',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Join code'), '12');
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid join code'), findsOneWidget);
    });

    testWidgets('an unresolved code reports the game as unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: JoinLobbyScreen(
            codeResolver:
                (code, {timeout = const Duration(seconds: 5)}) async =>
                    const JoinCodeResolution.unavailable(),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Your name'),
        'Mia',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Join code'),
        '483729',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Game unavailable'), findsOneWidget);
    });

    testWidgets('the join-code field starts empty (no pre-fill)', (
      tester,
    ) async {
      // Regression (M18.5 real-device bug): the 6-digit code field must
      // never be pre-populated on a fresh Join Game screen — no default
      // value, no restoration, no autofill.
      await tester.pumpWidget(MaterialApp(home: JoinLobbyScreen()));
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Join code'),
      );
      expect(field.controller!.text, isEmpty);
      expect(field.autofillHints, isEmpty);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).last)
            .controller
            .text,
        isEmpty,
      );
    });

    testWidgets(
      'a wrong code fails fast with a clear message instead of hanging',
      (tester) async {
        var resolved = false;
        await tester.pumpWidget(
          MaterialApp(
            home: JoinLobbyScreen(
              codeResolver:
                  (code, {timeout = const Duration(seconds: 4)}) async {
                    resolved = true;
                    return const JoinCodeResolution.notFound();
                  },
            ),
          ),
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Your name'),
          'Mia',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Join code'),
          '999999',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Join'));
        await tester.pumpAndSettle();

        expect(resolved, isTrue);
        expect(find.textContaining('No game found'), findsOneWidget);
        // The user is still on the Join Game screen and can correct the code.
        expect(find.text('Scan QR Code'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Join'), findsOneWidget);
      },
    );

    testWidgets('repeated taps cannot create duplicate join attempts', (
      tester,
    ) async {
      var calls = 0;
      final gate = Completer<JoinCodeResolution>();
      await tester.pumpWidget(
        MaterialApp(
          home: JoinLobbyScreen(
            codeResolver: (code, {timeout = const Duration(seconds: 4)}) {
              calls++;
              return gate.future;
            },
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Your name'),
        'Mia',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Join code'),
        '483729',
      );
      // Capture the button's position before the first tap: once the join
      // starts the label changes to “Connecting…” and the finder would no
      // longer match, but the (disabled) button stays in place.
      final joinButton = find.widgetWithText(FilledButton, 'Join');
      final joinCenter = tester.getCenter(joinButton);
      await tester.tapAt(joinCenter);
      await tester.pump();
      await tester.tapAt(joinCenter);
      await tester.tapAt(joinCenter);
      await tester.pump();

      expect(calls, 1, reason: 'only one join attempt may be in flight');
      // While joining, the button switches to the Connecting state.
      expect(find.text('Connecting…'), findsOneWidget);

      gate.complete(const JoinCodeResolution.notFound());
      await tester.pumpAndSettle();
      expect(find.textContaining('No game found'), findsOneWidget);
    });

    testWidgets('a valid QR payload shows Connecting… immediately', (
      tester,
    ) async {
      // The join is real socket I/O; keep the resolver pending so the test
      // can assert the immediate UI state after a valid scan.
      final payload = JoinPayload(
        sessionId: 'connecting-ui',
        joinCode: '483729',
        relayUrl: 'ws://127.0.0.1:1', // closed port: the connect fails fast
      ).encode();
      await tester.pumpWidget(
        MaterialApp(
          home: JoinLobbyScreen(scanPayloadProvider: () async => payload),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Your name'),
        'Mia',
      );
      await tester.tap(find.text('Scan QR Code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The join attempt is in flight against an unreachable relay: the UI
      // must say Connecting… rather than appearing to do nothing.
      expect(find.text('Connecting…'), findsWidgets);
      // The relay port is closed on loopback, so the connection fails fast;
      // the failure must surface as a concise user-facing message — never a
      // raw SocketException / connection-refused error.
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();
      expect(find.textContaining('Connection failed'), findsOneWidget);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.textContaining('Connection refused'), findsNothing);
      expect(find.textContaining('TimeoutException'), findsNothing);
      // A fast failure is not a slow relay wake — the waking hint must stay
      // hidden.
      expect(find.text('Waking the multiplayer relay…'), findsNothing);
    });

    testWidgets('a relay join still in flight after a few seconds shows the '
        'waking-relay message', (tester) async {
      // A TCP listener that accepts the WebSocket upgrade attempt but
      // never answers keeps the client's connect pending — exactly what a
      // relay that is still waking looks like to the app.
      final stall = await tester.runAsync(
        () => ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
      );
      final server = stall!;
      final accepted = <Socket>[];
      final sub = server.listen((socket) => accepted.add(socket));
      addTearDown(() async {
        for (final socket in accepted) {
          try {
            socket.destroy();
          } catch (_) {}
        }
        await sub.cancel();
        await server.close();
      });

      final payload = JoinPayload(
        sessionId: 'waking-ui',
        joinCode: '483729',
        relayUrl: 'ws://127.0.0.1:${server.port}',
      ).encode();
      await tester.pumpWidget(
        MaterialApp(
          home: JoinLobbyScreen(scanPayloadProvider: () async => payload),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Your name'),
        'Mia',
      );
      await tester.tap(find.text('Scan QR Code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The join is still in flight: plain "Connecting…" with no waking
      // hint yet.
      expect(find.text('Connecting…'), findsWidgets);
      expect(find.text('Waking the multiplayer relay…'), findsNothing);

      // After a meaningful delay the UI says the relay may be waking, and
      // the loading state stays active (the button is still disabled).
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('Waking the multiplayer relay…'), findsOneWidget);
      expect(find.text('Connecting…'), findsWidgets);

      // Both attempts (initial + one retry) time out; the state clears to
      // a friendly error and the waking hint disappears.
      await tester.pump(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Waking the multiplayer relay…'), findsNothing);
      expect(find.textContaining('Connection failed'), findsOneWidget);

      // Drain the WebSocket close-handshake timeout Dart schedules, so no
      // fake timers are pending when the test body ends.
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets(
      'a valid QR payload joins a real relay-hosted game through the UI',
      (tester) async {
        final relay = RelayServer();
        await tester.runAsync(() => relay.start(port: 0));
        addTearDown(() => tester.runAsync(() => relay.stop()));
        final relayUrl = 'ws://127.0.0.1:${relay.port}';
        final host = HostSession(
          sessionId: 'qr-ui',
          joinCode: '483729',
          transport: RelayMultiplayerTransport(relayUrl: relayUrl),
        );
        await tester.runAsync(
          () => host.start(displayName: 'G', hostName: 'H', port: 0),
        );
        final payload = JoinPayload(
          sessionId: host.sessionId,
          joinCode: '483729',
          relayUrl: relayUrl,
        ).encode();

        await tester.pumpWidget(
          MaterialApp(
            home: JoinLobbyScreen(
              relayUrl: relayUrl,
              scanPayloadProvider: () async => payload,
            ),
          ),
        );
        // The join is a real WebSocket handshake: run the tap and the
        // handshake inside a single real-async window so the sockets can
        // progress. Instead of sleeping a fixed amount, poll until the join
        // completes (or a deadline passes) — a fixed delay is too short when
        // the machine is under load and would otherwise flake.
        await tester.runAsync(() async {
          await tester.enterText(
            find.widgetWithText(TextField, 'Your name'),
            'Mia',
          );
          await tester.tap(find.text('Scan QR Code'));
          await tester.pump();
          final deadline = DateTime.now().add(const Duration(seconds: 15));
          while (find.textContaining('Joined as').evaluate().isEmpty &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await tester.pump();
          }
        });
        await tester.pumpAndSettle();

        expect(find.textContaining('Joined as'), findsOneWidget);
        expect(find.text('H'), findsOneWidget);
        // A warm join completes well before the waking hint's delay, so the
        // hint must never have appeared.
        expect(find.text('Waking the multiplayer relay…'), findsNothing);

        // Stopping the host closes the client's socket through the relay.
        // Give the client a real-async window to observe the close and close
        // its own WebSocket, then drain the 5s close-handshake timeout that
        // Dart's WebSocket.close() schedules (fake zone, so the test would
        // otherwise end with a pending timer under load — see the host-lobby
        // test above).
        await tester.runAsync(() async {
          await host.stop();
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
        await tester.pump(const Duration(seconds: 6));
      },
    );
  });

  group('join via QR payload and code over the relay (integration)', () {
    Future<(RelayServer, HostSession, String)> startRelayHost(
      String sessionId,
      String code,
    ) async {
      final relay = RelayServer();
      await relay.start(port: 0);
      final relayUrl = 'ws://127.0.0.1:${relay.port}';
      final host = HostSession(
        sessionId: sessionId,
        joinCode: code,
        transport: RelayMultiplayerTransport(relayUrl: relayUrl),
      );
      await host.start(displayName: 'G', hostName: 'H', port: 0);
      return (relay, host, relayUrl);
    }

    test('a client joins a real host using a parsed QR payload', () async {
      final (relay, host, relayUrl) = await startRelayHost('qr-1', '483729');
      final payload = JoinPayload(
        sessionId: host.sessionId,
        joinCode: '483729',
        relayUrl: relayUrl,
      ).encode();

      final parsed = JoinPayload.parse(payload);
      expect(parsed, isNotNull);
      expect(parsed!.joinCode, '483729');
      expect(parsed.relayUrl, relayUrl);

      final client = ClientSession(
        sessionId: parsed.sessionId,
        playerName: 'Mia',
      );
      final result = await client.joinRelay(relayUrl: parsed.relayUrl);
      expect(result.isAccepted, isTrue);
      expect(host.roster.length, 2);
      expect(host.roster.map((p) => p.name), contains('Mia'));

      await client.disconnect();
      await host.stop();
      await relay.stop();
    });

    test('a client joins using a code resolved from the relay', () async {
      final (relay, host, relayUrl) = await startRelayHost('code-1', '222222');

      final lookup = await lookupJoinCodeOnRelay(relayUrl, '222222');
      expect(lookup, isA<RelayLookupFound>());
      final found = lookup as RelayLookupFound;
      expect(found.sessionId, host.sessionId);

      final client = ClientSession(
        sessionId: found.sessionId,
        playerName: 'Leo',
      );
      final result = await client.joinRelay(relayUrl: relayUrl);
      expect(result.isAccepted, isTrue);
      expect(host.roster.length, 2);

      await client.disconnect();
      await host.stop();
      await relay.stop();
    });

    test('a wrong code fails fast against the relay', () async {
      final (relay, host, relayUrl) = await startRelayHost('code-2', '222222');

      final lookup = await lookupJoinCodeOnRelay(relayUrl, '999999');
      expect(lookup, isA<RelayLookupNotFound>());

      await host.stop();
      await relay.stop();
    });

    test('an expired/unavailable session cannot be joined', () async {
      final (relay, host, relayUrl) = await startRelayHost('gone', '483729');
      await host.stop(); // the host vanishes before anyone joins

      final client = ClientSession(sessionId: 'gone', playerName: 'X');
      final result = await client.joinRelay(relayUrl: relayUrl);
      expect(result.isAccepted, isFalse);
      // The relay reports the session is gone; the join maps that to the
      // friendly session-ended outcome.
      expect(result.outcome, JoinOutcome.sessionEnded);

      await client.disconnect();
      await relay.stop();
    });

    test(
      'a payload with a wrong session id still cannot bypass the host',
      () async {
        final (relay, host, relayUrl) = await startRelayHost(
          'real-session',
          '483729',
        );

        // A forged QR claiming a different session id cannot join: the relay
        // only routes a session id that was actually registered by a host, so
        // the forged id is rejected before it ever reaches the host.
        final forged = JoinPayload(
          sessionId: 'forged-session',
          joinCode: '483729',
          relayUrl: relayUrl,
        ).encode();
        final parsed = JoinPayload.parse(forged)!;
        final client = ClientSession(
          sessionId: parsed.sessionId,
          playerName: 'Eve',
        );
        final result = await client.joinRelay(relayUrl: parsed.relayUrl);
        expect(result.isAccepted, isFalse);
        expect(host.roster.length, 1, reason: 'Eve never reached the host');

        await client.disconnect();
        await host.stop();
        await relay.stop();
      },
    );
  });
}
