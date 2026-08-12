import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/multiplayer/discovery.dart';
import 'package:turtle_king/multiplayer/transport.dart';

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  group('beacon encoding', () {
    test('encodes the session identity, name, and port', () {
      final raw = encodeBeacon(
        sessionId: 'tk-abc123',
        displayName: 'Friday Night',
        port: 41321,
      );
      expect(raw, contains('tk-abc123'));
      expect(raw, contains('Friday Night'));
      expect(raw, contains('41321'));
    });

    test('parseBeacon accepts a valid beacon', () {
      final raw = encodeBeacon(
        sessionId: 'tk-abc123',
        displayName: 'Friday Night',
        port: 41321,
      );
      final session = parseBeacon(raw, InternetAddress('192.168.1.5'));
      expect(session, isNotNull);
      expect(session!.sessionId, 'tk-abc123');
      expect(session.displayName, 'Friday Night');
      expect(session.port, 41321);
      expect(session.hostAddress, '192.168.1.5');
      expect(session.joinCode, isNull);
    });

    test('the beacon carries the join code when the host has one', () {
      final raw = encodeBeacon(
        sessionId: 'tk-abc123',
        displayName: 'Friday Night',
        port: 41321,
        joinCode: '483729',
      );
      expect(raw, contains('483729'));
      final session = parseBeacon(raw, InternetAddress('192.168.1.5'));
      expect(session!.joinCode, '483729');
    });

    test('a beacon with an invalid join code is rejected', () {
      final raw = encodeBeacon(
        sessionId: 'tk-abc123',
        displayName: 'Friday Night',
        port: 41321,
        joinCode: '48372', // five digits
      );
      expect(parseBeacon(raw, InternetAddress('192.168.1.5')), isNull);
    });

    test('parseBeacon rejects malformed payloads without throwing', () {
      expect(parseBeacon('not json', InternetAddress('1.2.3.4')), isNull);
      expect(parseBeacon('{}', InternetAddress('1.2.3.4')), isNull);
      expect(parseBeacon('[]', InternetAddress('1.2.3.4')), isNull);
      expect(
        parseBeacon(
          '{"v":1,"type":"BEACON","sessionId":"","displayName":"x","port":1}',
          InternetAddress('1.2.3.4'),
        ),
        isNull,
      );
      expect(
        parseBeacon(
          '{"v":1,"type":"OTHER","sessionId":"s","displayName":"x","port":1}',
          InternetAddress('1.2.3.4'),
        ),
        isNull,
      );
      expect(
        parseBeacon(
          '{"v":99,"type":"BEACON","sessionId":"s","displayName":"x","port":1}',
          InternetAddress('1.2.3.4'),
        ),
        isNull,
      );
      expect(
        parseBeacon(
          '{"v":1,"type":"BEACON","sessionId":"s","displayName":"x","port":0}',
          InternetAddress('1.2.3.4'),
        ),
        isNull,
      );
      expect(
        parseBeacon(
          '{"v":1,"type":"BEACON","sessionId":"s","displayName":"x","port":70000}',
          InternetAddress('1.2.3.4'),
        ),
        isNull,
      );
      expect(
        parseBeacon(
          '{"v":1,"type":"BEACON","sessionId":"s","displayName":"x","port":-1}',
          InternetAddress('1.2.3.4'),
        ),
        isNull,
      );
    });
  });

  group('UdpBeaconDiscovery over loopback', () {
    test('a listener receives a beacon advertised on the same group', () async {
      // Use a dedicated port so parallel test runs cannot collide with
      // other suites (and reuseAddress keeps multiple hosts on one port).
      const port = 5359;
      final listener = UdpBeaconDiscovery(
        beaconTarget: InternetAddress('239.255.77.78'),
        discoveryPort: port,
      );
      final found = <DiscoveredSession>[];
      final sub = listener.discovered.listen(found.add);

      final host = UdpBeaconDiscovery(
        beaconTarget: InternetAddress('239.255.77.78'),
        discoveryPort: port,
        beaconInterval: const Duration(milliseconds: 100),
      );
      await host.advertise(
        sessionId: 'tk-loop1',
        displayName: 'Loop Game',
        port: 41321,
      );

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (found.isEmpty && DateTime.now().isBefore(deadline)) {
        await pump();
      }

      expect(found, isNotEmpty, reason: 'listener should discover the host');
      expect(found.first.sessionId, 'tk-loop1');
      expect(found.first.displayName, 'Loop Game');
      expect(found.first.port, 41321);

      await host.stop();
      await listener.stop();
      await sub.cancel();
    });

    test('the discovery stream supports the lobby listener and a code '
        'resolution listener at the same time', () async {
      // Regression (M18.5 real-device bug): the discovery stream used to
      // be single-subscription, so attaching resolveJoinCode's one-shot
      // listener on top of the lobby's live listener threw
      // "Stream has already been listened to", leaving the join stuck
      // forever. Both listeners must receive beacons concurrently.
      const port = 5361;
      final listener = UdpBeaconDiscovery(
        beaconTarget: InternetAddress('239.255.77.81'),
        discoveryPort: port,
      );
      final live = <DiscoveredSession>[];
      final liveSub = listener.discovered.listen(live.add);

      // A second, concurrent listener — exactly what resolveJoinCode
      // does when the join lobby already listens.
      final resolutionFuture = resolveJoinCode(
        listener.discovered,
        '483729',
        timeout: const Duration(seconds: 5),
      );

      final host = UdpBeaconDiscovery(
        beaconTarget: InternetAddress('239.255.77.81'),
        discoveryPort: port,
        beaconInterval: const Duration(milliseconds: 100),
      );
      await host.advertise(
        sessionId: 'tk-loop2',
        displayName: 'Loop Game',
        port: 41321,
        joinCode: '483729',
      );

      final resolution = await resolutionFuture;
      expect(resolution.isFound, isTrue);
      expect(resolution.session!.sessionId, 'tk-loop2');
      expect(
        live,
        isNotEmpty,
        reason:
            'the lobby listener must still receive beacons while '
            'resolution is active',
      );

      await host.stop();
      await listener.stop();
      await liveSub.cancel();
    });

    test('resolveJoinCode finds a session by its code on the stream', () async {
      final controller = StreamController<DiscoveredSession>();
      final future = resolveJoinCode(
        controller.stream,
        '483729',
        timeout: const Duration(seconds: 2),
      );
      controller.add(
        DiscoveredSession(
          sessionId: 'other',
          displayName: 'Other',
          hostAddress: '10.0.0.2',
          joinCode: '222222',
        ),
      );
      controller.add(
        DiscoveredSession(
          sessionId: 'tk-match',
          displayName: 'Match',
          hostAddress: '192.168.1.5',
          port: 41321,
          joinCode: '483729',
        ),
      );
      final resolution = await future;
      expect(resolution.isFound, isTrue);
      expect(resolution.session!.sessionId, 'tk-match');
      expect(resolution.session!.hostAddress, '192.168.1.5');
      await controller.close();
    });

    test('resolveJoinCode prefers the first match on a collision', () async {
      // Two hosts on the same LAN may draw the same code; resolution picks
      // the first match (a locator, not an identity).
      final controller = StreamController<DiscoveredSession>();
      final future = resolveJoinCode(
        controller.stream,
        '483729',
        timeout: const Duration(seconds: 2),
      );
      controller.add(
        DiscoveredSession(
          sessionId: 'first',
          displayName: 'First',
          hostAddress: '192.168.1.5',
          joinCode: '483729',
        ),
      );
      controller.add(
        DiscoveredSession(
          sessionId: 'second',
          displayName: 'Second',
          hostAddress: '192.168.1.6',
          joinCode: '483729',
        ),
      );
      final resolution = await future;
      expect(resolution.isFound, isTrue);
      expect(resolution.session!.sessionId, 'first');
      await controller.close();
    });

    test(
      'resolveJoinCode matches an already-seen session immediately',
      () async {
        // A valid code must NOT wait for the next beacon cycle or the
        // timeout: if the session is already on screen, resolve instantly.
        final controller = StreamController<DiscoveredSession>();
        final stopwatch = Stopwatch()..start();
        final resolution = await resolveJoinCode(
          controller.stream,
          '483729',
          alreadySeen: const [
            DiscoveredSession(
              sessionId: 'known',
              displayName: 'Known',
              hostAddress: '192.168.1.5',
              joinCode: '483729',
            ),
          ],
          timeout: const Duration(seconds: 30),
        );
        stopwatch.stop();
        expect(resolution.isFound, isTrue);
        expect(resolution.session!.sessionId, 'known');
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 1)),
          reason: 'an already-discovered code resolves without any wait',
        );
        // No listener ever attached (the fast path returns before
        // subscribing), so the controller must be closed without awaiting
        // its done event, which would otherwise never be delivered.
        unawaited(controller.close());
      },
    );

    test(
      'resolveJoinCode reports unavailable when the stream errors',
      () async {
        final controller = StreamController<DiscoveredSession>();
        final future = resolveJoinCode(
          controller.stream,
          '483729',
          timeout: const Duration(seconds: 5),
        );
        controller.addError(StateError('discovery socket died'));
        final resolution = await future;
        expect(resolution.status, JoinCodeResolveStatus.unavailable);
        expect(resolution.session, isNull);
        await controller.close();
      },
    );

    test(
      'resolveJoinCode returns notFound for unknown codes and bad input',
      () async {
        final controller = StreamController<DiscoveredSession>();
        final unknown = resolveJoinCode(
          controller.stream,
          '999999',
          timeout: const Duration(milliseconds: 150),
        );
        final resolution = await unknown;
        expect(resolution.status, JoinCodeResolveStatus.notFound);
        expect(resolution.session, isNull);
        expect(
          await resolveJoinCode(
            controller.stream,
            '123',
            timeout: const Duration(seconds: 5),
          ),
          isA<JoinCodeResolution>().having(
            (r) => r.status,
            'status',
            JoinCodeResolveStatus.notFound,
          ),
          reason: 'invalid codes never resolve',
        );
        await controller.close();
      },
    );

    test('malformed datagrams on the discovery port are ignored', () async {
      const port = 5360;
      final listener = UdpBeaconDiscovery(
        beaconTarget: InternetAddress('239.255.77.79'),
        discoveryPort: port,
      );
      final found = <DiscoveredSession>[];
      final sub = listener.discovered.listen(found.add);

      // Send garbage directly at the discovery port.
      final sender = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sender.send(
        utf8.encode('not a beacon'),
        InternetAddress('127.0.0.1'),
        port,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(found, isEmpty);
      await listener.stop();
      await sub.cancel();
      sender.close();
    });
  });
}
