import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_start_screen.dart';
import 'package:turtle_king/how_to_play_screen.dart';
import 'package:turtle_king/main.dart';

void main() {
  group('HowToPlayScreen', () {
    testWidgets('renders the How to Play title', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      expect(find.text('How to Play'), findsOneWidget);
      expect(find.byType(HowToPlayScreen), findsOneWidget);
    });

    testWidgets('shows every rules section in order', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      for (final title in [
        'The Goal',
        'Setting Up',
        'Your Two Cards',
        'Pass the Phone',
        'The Center Pile',
        'YAMADA',
        'Draw to the Center',
        'Wrong YAMADA Calls',
        'Penalty Cups',
        'Multiple Rounds',
        'Elimination',
        'Turtle King',
        'Current Project Rules',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
    });

    testWidgets('explains the private two-card hands', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      expect(find.textContaining('two private cards'), findsOneWidget);
      expect(find.textContaining('only for you'), findsOneWidget);
    });

    testWidgets('explains the pass-and-play privacy flow', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      expect(find.textContaining('neutral'), findsOneWidget);
      expect(find.textContaining('tap Continue'), findsOneWidget);
    });

    testWidgets('explains the center pile', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      expect(find.textContaining('face-up center pile'), findsOneWidget);
      expect(find.textContaining('current center card'), findsWidgets);
    });

    testWidgets('explains the strictly-between YAMADA rule', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      expect(find.textContaining('strictly between'), findsWidgets);
      // The example makes the strict rule concrete.
      expect(find.textContaining('4, 6, and 8 qualify'), findsOneWidget);
      expect(find.textContaining('3, 9, and 10 do not'), findsOneWidget);
      // Card values are spelled out.
      expect(find.textContaining('Ace = 1'), findsOneWidget);
      expect(find.textContaining('King = 13'), findsOneWidget);
    });

    testWidgets('explains drawing to the center', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      expect(
        find.textContaining('draw the next card from the remaining deck'),
        findsOneWidget,
      );
      expect(find.textContaining('top of the center pile'), findsOneWidget);
    });

    testWidgets('explains the wrong YAMADA call as a penalized action', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      expect(
        find.textContaining('allowed, but it is penalized'),
        findsOneWidget,
      );
      expect(find.textContaining('stays on the pile'), findsOneWidget);
      expect(find.textContaining('one penalty point'), findsOneWidget);
    });

    testWidgets('explains the penalty cup system', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      // Also repeated in the Current Project Rules assumptions list.
      expect(find.textContaining('3 penalty points'), findsWidgets);
      expect(find.textContaining('full cup'), findsWidgets);
      expect(find.textContaining('abstract penalty counter'), findsOneWidget);
    });

    testWidgets('explains multiple rounds and the no-reshuffle deck', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      expect(find.textContaining('several rounds'), findsOneWidget);
      // Also repeated in the Elimination section and assumptions list.
      expect(find.textContaining('not reshuffled'), findsWidgets);
      expect(
        find.textContaining('fewer than two active players'),
        findsWidgets,
      );
    });

    testWidgets('explains elimination as a current project rule', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      expect(find.textContaining('2 full cups by default'), findsOneWidget);
      expect(find.textContaining('Current project rule'), findsOneWidget);
      expect(find.textContaining('no longer receive hands'), findsOneWidget);
    });

    testWidgets('labels the Turtle King rule as a project assumption', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      expect(find.textContaining('fewest total captures'), findsOneWidget);
      expect(
        find.textContaining('not an official Turtle King rule'),
        findsOneWidget,
      );
      expect(find.textContaining('no hidden tie-breaker'), findsOneWidget);
    });

    testWidgets('shows the Current Project Rules assumptions section', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      expect(find.text('Current Project Rules'), findsOneWidget);
      expect(
        find.textContaining('project assumptions, not official rules'),
        findsOneWidget,
      );
      expect(find.textContaining('default cup capacity is 3'), findsOneWidget);
      expect(
        find.textContaining('default elimination threshold is 2'),
        findsOneWidget,
      );
      expect(find.textContaining('fewest cumulative captures'), findsOneWidget);
    });

    testWidgets('content is scrollable and lower sections can be reached', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      expect(find.byType(Scrollable), findsWidgets);
      // The final section starts below the fold.
      await tester.scrollUntilVisible(
        find.text('Current Project Rules'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Current Project Rules'), findsOneWidget);
    });

    testWidgets('works on a small phone viewport without clipping', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: HowToPlayScreen()));

      // No overflow/clipping exceptions on a small screen.
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Current Project Rules'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('back navigation returns from How to Play', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const HowToPlayScreen(),
                    ),
                  ),
                  child: const Text('open rules'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open rules'));
      await tester.pumpAndSettle();
      expect(find.byType(HowToPlayScreen), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(HowToPlayScreen), findsNothing);
      expect(find.text('open rules'), findsOneWidget);
    });

    test('the screen is stateless and needs no GameState', () {
      // A const constructor proves the screen takes no GameState argument,
      // so opening it can never create or mutate game state.
      const screen = HowToPlayScreen();
      expect(screen, isA<StatelessWidget>());
      expect(screen, isA<HowToPlayScreen>());
    });

    testWidgets('opening How to Play from the app creates no game widgets', (
      tester,
    ) async {
      await tester.pumpWidget(const TurtleKingApp());
      // Advance past the splash screen to the home screen.
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();
      expect(find.byType(GameStartScreen), findsNothing);

      await tester.tap(find.text('How to Play'));
      await tester.pumpAndSettle();

      expect(find.byType(HowToPlayScreen), findsOneWidget);
      // No gameplay screen exists behind or beside the rules.
      expect(find.byType(GameStartScreen), findsNothing);
    });
  });
}
