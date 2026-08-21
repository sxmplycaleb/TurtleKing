import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';

List<Player> makePlayers(int count) => [
  for (var i = 0; i < count; i++)
    Player(id: 'player-$i', name: 'Player $i', color: PlayerColors.palette[i]),
];

int handTotal(GameState game, Player player) =>
    game.handOf(player).fold(0, (sum, card) => sum + card.value);

/// Moves the game through the entire viewing phase so pouring starts.
void viewAll(GameState game) {
  for (var i = 0; i < game.currentPlayerCount; i++) {
    game.revealCurrentPlayer();
    game.passToNextPlayer();
  }
  expect(game.pouringStarted, isTrue);
}

/// Every active player holds out once, completing the round's reveal.
void everyoneHoldsOut(GameState game) {
  final count = game.activePlayerCount;
  for (var i = 0; i < count; i++) {
    game.holdOut(game.pourCurrentPlayer);
  }
  expect(game.roundComplete, isTrue);
}

/// Advances the game through enough rounds so that [target] player has
/// accumulated at least [drinks] drinks.
///
/// Round N gives the smallest hand (N) + 1 extra = (N+1) drinks.
/// Round 1: 2 drinks to the smallest.
/// Round 2: 3 drinks to the smallest.
/// Round 3: 4 drinks to the smallest.
/// etc.
///
/// Because the smallest hand changes between rounds, this helper plays
/// many rounds and checks after each one.
void ensureDrinks(
  GameState game,
  Player target,
  int drinks, {
  bool saveRestore = false,
  GameState Function(GameState)? restorer,
}) {
  var rounds = 0;
  while (game.drinksOf(target) < drinks && !game.gameComplete) {
    viewAll(game);
    everyoneHoldsOut(game);
    if (!game.canStartNextRound) break;
    game.startNextRound();
    rounds++;
    if (rounds > 50) break; // safety
  }
}

/// Complete a full round (view + hold out).
void completeRound(GameState game) {
  viewAll(game);
  everyoneHoldsOut(game);
}
