import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/main.dart';
import 'package:turtle_king/multiplayer/host_lobby_screen.dart';
import 'package:turtle_king/multiplayer/join_lobby_screen.dart';
import 'package:turtle_king/multiplayer/menu_screen.dart';

/// Pumps the full app and advances past the splash screen so the home
/// screen is on stage.
Future<void> pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(const TurtleKingApp());
  await tester.pump(const Duration(milliseconds: 1300));
  await tester.pumpAndSettle();
}

void main() {
  group('multiplayer UI flow', () {
    testWidgets('Home shows a Multiplayer button that opens the menu', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.text('Multiplayer'), findsOneWidget);
      await tester.tap(find.text('Multiplayer'));
      await tester.pumpAndSettle();

      expect(find.byType(MultiplayerMenuScreen), findsOneWidget);
      expect(find.text('Host Game'), findsOneWidget);
      expect(find.text('Join Game'), findsOneWidget);
    });

    testWidgets('Host Game opens the host lobby', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.text('Multiplayer'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Host Game'));
      await tester.pumpAndSettle();

      expect(find.byType(HostLobbyScreen), findsOneWidget);
    });

    testWidgets('Join Game opens the join lobby', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.text('Multiplayer'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Join Game'));
      await tester.pumpAndSettle();

      expect(find.byType(JoinLobbyScreen), findsOneWidget);
    });

    /// Expands the collapsed Developer options section (which holds the LAN
    /// discovery list and the manual-IP debug fallback), then the manual-IP
    /// tile, and scrolls its join button into view so tests can drive the
    /// debug join path.
    Future<void> openManualIp(WidgetTester tester) async {
      await tester.tap(find.text('Developer options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manual setup (host IP)'));
      await tester.pumpAndSettle();
      final joinByIp = find.widgetWithText(FilledButton, 'Join by IP');
      await tester.scrollUntilVisible(
        joinByIp,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('join lobby rejects a missing name before contacting a host', (
      tester,
    ) async {
      await pumpHome(tester);
      await tester.tap(find.text('Multiplayer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join Game'));
      await tester.pumpAndSettle();

      // Leave the name empty, enter a valid IP, and try to join.
      await openManualIp(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Host IPv4'),
        '192.168.1.50',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join by IP'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your name first.'), findsOneWidget);
    });

    testWidgets('join lobby rejects an invalid IPv4 address', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.text('Multiplayer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join Game'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Your name'),
        'Mia',
      );
      await openManualIp(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Host IPv4'),
        'not-an-ip',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join by IP'));
      await tester.pumpAndSettle();

      expect(find.textContaining('valid IPv4'), findsOneWidget);
    });

    testWidgets('join lobby rejects an invalid port', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.text('Multiplayer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join Game'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Your name'),
        'Mia',
      );
      await openManualIp(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Host IPv4'),
        '192.168.1.50',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Port'), '99999');
      await tester.tap(find.widgetWithText(FilledButton, 'Join by IP'));
      await tester.pumpAndSettle();

      expect(find.textContaining('valid port'), findsOneWidget);
    });
  });
}
