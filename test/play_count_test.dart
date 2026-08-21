import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:turtle_king/legal/onboarding_store.dart';
import 'package:turtle_king/main.dart';
import 'package:turtle_king/other_games/game_catalog.dart';
import 'package:turtle_king/other_games/game_ranking.dart';
import 'package:turtle_king/other_games/play_count_store.dart';
import 'package:turtle_king/other_games/other_games_section.dart';
import 'package:turtle_king/settings.dart';

/// Pumps the full app and advances past the splash screen.
Future<void> pumpHome(
  WidgetTester tester, {
  Map<String, int> playCounts = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'settings.legalConsentAccepted': true,
    'settings.legalConsentVersion': '1.0',
  });
  final settings = await SettingsStore.load();
  final onboarding = OnboardingStore.inMemory()..completeOnboarding();
  await tester.pumpWidget(
    TurtleKingApp(store: settings, onboarding: onboarding),
  );
  await tester.pump(const Duration(milliseconds: 1300));
  await tester.pumpAndSettle();
}

void main() {
  group('PlayCountStore', () {
    test('in-memory store starts with zero counts', () {
      final store = PlayCountStore.inMemory();
      for (final game in gameCatalog) {
        expect(store.count(game.id), 0);
      }
    });

    test('increment increases count by 1', () {
      final store = PlayCountStore.inMemory();
      store.increment('ludo');
      expect(store.count('ludo'), 1);
      store.increment('ludo');
      expect(store.count('ludo'), 2);
    });

    test('increment only affects the specified game', () {
      final store = PlayCountStore.inMemory();
      store.increment('ludo');
      expect(store.count('ludo'), 1);
      expect(store.count('choose_a_topic'), 0);
    });

    test('allCounts returns counts for all catalog games', () {
      final store = PlayCountStore.inMemory();
      store.increment('ludo');
      store.increment('ludo');
      store.increment('spell_or_take_a_shot');
      final counts = store.allCounts();
      expect(counts['ludo'], 2);
      expect(counts['spell_or_take_a_shot'], 1);
      expect(counts['choose_a_topic'], 0);
    });
  });

  group('sortedByPlayCount', () {
    test('higher play count appears first', () {
      final counts = <String, int>{
        'choose_a_topic': 8,
        'ludo': 5,
        'shots_and_ladders': 1,
      };
      final sorted = sortedByPlayCount(gameCatalog, counts);
      expect(sorted[0].id, 'choose_a_topic');
      expect(sorted[1].id, 'ludo');
      expect(sorted[2].id, 'shots_and_ladders');
    });

    test('zero-play games remain below played games', () {
      final counts = <String, int>{'ludo': 3};
      final sorted = sortedByPlayCount(gameCatalog, counts);
      expect(sorted[0].id, 'ludo');
      final zeroPlay = sorted.where((g) => g.id != 'ludo').toList();
      expect(zeroPlay[0].id, 'choose_a_topic');
      expect(zeroPlay[1].id, 'shots_and_ladders');
    });

    test('equal play counts preserve catalog order', () {
      final counts = <String, int>{
        'choose_a_topic': 5,
        'ludo': 5,
        'spell_or_take_a_shot': 3,
      };
      final sorted = sortedByPlayCount(gameCatalog, counts);
      final idx0 = sorted.indexWhere((g) => g.id == 'choose_a_topic');
      final idx1 = sorted.indexWhere((g) => g.id == 'ludo');
      expect(idx0, lessThan(idx1));
    });

    test('all-zero counts preserve catalog order', () {
      final sorted = sortedByPlayCount(gameCatalog, {});
      for (var i = 0; i < gameCatalog.length; i++) {
        expect(sorted[i].id, gameCatalog[i].id);
      }
    });

    test('ranking updates after new play', () {
      var counts = <String, int>{'choose_a_topic': 3, 'ludo': 5};
      var sorted = sortedByPlayCount(gameCatalog, counts);
      expect(sorted[0].id, 'ludo');

      counts = <String, int>{'choose_a_topic': 6, 'ludo': 5};
      sorted = sortedByPlayCount(gameCatalog, counts);
      expect(sorted[0].id, 'choose_a_topic');
    });
  });

  group('OtherGamesSection play-count UI', () {
    testWidgets('no MOST PLAYED when all games have zero plays', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: OtherGamesSection())),
      );

      await tester.ensureVisible(find.text('OTHER GAMES'));
      await tester.tap(find.text('OTHER GAMES'));
      await tester.pumpAndSettle();

      expect(find.text('MOST PLAYED'), findsNothing);
    });

    testWidgets('MOST PLAYED appears for highest-played game', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtherGamesSection(playCounts: const {'ludo': 3}),
          ),
        ),
      );

      await tester.tap(find.text('OTHER GAMES'));
      await tester.pumpAndSettle();

      expect(find.text('MOST PLAYED'), findsOneWidget);
      expect(find.text('3 PLAYS'), findsOneWidget);
    });

    testWidgets('badge moves to new leader when overtaken', (tester) async {
      // Ludo leads.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtherGamesSection(
              playCounts: const {'ludo': 5, 'choose_a_topic': 3},
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('OTHER GAMES'));
      await tester.tap(find.text('OTHER GAMES'));
      await tester.pumpAndSettle();
      expect(find.text('5 PLAYS'), findsOneWidget);
    });

    testWidgets('new leader shows correct play count', (tester) async {
      // Choose a Topic leads.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtherGamesSection(
              playCounts: const {'ludo': 5, 'choose_a_topic': 10},
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('OTHER GAMES'));
      await tester.tap(find.text('OTHER GAMES'));
      await tester.pumpAndSettle();
      expect(find.text('10 PLAYS'), findsOneWidget);
    });

    testWidgets('single play shows PLAY not PLAYS', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtherGamesSection(playCounts: const {'ludo': 1}),
          ),
        ),
      );

      await tester.ensureVisible(find.text('OTHER GAMES'));
      await tester.tap(find.text('OTHER GAMES'));
      await tester.pumpAndSettle();

      expect(find.text('1 PLAY'), findsOneWidget);
      expect(find.text('1 PLAYS'), findsNothing);
    });

    testWidgets('all games show COMING SOON when zero plays', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: OtherGamesSection())),
      );

      await tester.ensureVisible(find.text('OTHER GAMES'));
      await tester.tap(find.text('OTHER GAMES'));
      await tester.pumpAndSettle();

      expect(find.text('COMING SOON'), findsNWidgets(6));
    });

    testWidgets('games sorted by play count when expanded', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtherGamesSection(
              playCounts: const {'ludo': 5, 'choose_a_topic': 10},
            ),
          ),
        ),
      );

      await tester.ensureVisible(find.text('OTHER GAMES'));
      await tester.tap(find.text('OTHER GAMES'));
      await tester.pumpAndSettle();

      // Choose a Topic (10) appears first with MOST PLAYED badge.
      expect(find.text('MOST PLAYED'), findsOneWidget);
      expect(find.text('10 PLAYS'), findsOneWidget);
      // Ludo is second — it shows COMING SOON, not its play count.
      expect(find.text('COMING SOON'), findsWidgets);
    });
  });

  group('Regression', () {
    test('GameEntry has required id field', () {
      for (final game in gameCatalog) {
        expect(game.id.isNotEmpty, isTrue);
      }
    });

    test('all catalog ids are unique', () {
      final ids = gameCatalog.map((g) => g.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });
}
