import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/game_state.dart';
import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';

/// Builds a player with a stable id/name/color from [PlayerColors.palette].
Player testPlayer(int index, {String? id, String? name}) => Player(
  id: id ?? 'p$index',
  name: name ?? 'Player $index',
  color: PlayerColors.palette[index % PlayerColors.palette.length],
);

/// Builds a fresh game with [count] players and a deterministic seed.
GameState testGame(int count, {int seed = 7}) {
  return GameState(
    players: [for (var i = 0; i < count; i++) testPlayer(i)],
    random: Random(seed),
  );
}

/// Drives [game] through the entire private viewing phase so that pouring
/// begins (all players have revealed and passed).
GameState viewThrough(GameState game) {
  while (!game.allPlayersViewed && !game.pouringStarted) {
    if (!game.currentPlayerRevealed) {
      game.revealCurrentPlayer();
    } else {
      game.passToNextPlayer();
    }
  }
  return game;
}

/// Recursively asserts that [node] (a decoded JSON value) contains none of
/// [forbidden] as map keys.
void expectNoForbiddenKeys(Object? node, List<String> forbidden) {
  if (node is Map) {
    for (final key in node.keys) {
      expect(
        forbidden,
        isNot(contains(key)),
        reason: 'forbidden key "$key" appeared in public payload',
      );
      expectNoForbiddenKeys(node[key], forbidden);
    }
  } else if (node is List) {
    for (final item in node) {
      expectNoForbiddenKeys(item, forbidden);
    }
  }
}
