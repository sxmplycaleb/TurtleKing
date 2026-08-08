import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turtle_king/player.dart';
import 'package:turtle_king/player_colors.dart';

void main() {
  group('Player', () {
    test('stores id, name, and color', () {
      const player = Player(
        id: 'player-1',
        name: 'Alice',
        color: Color(0xFFD32F2F),
      );

      expect(player.id, 'player-1');
      expect(player.name, 'Alice');
      expect(player.color, const Color(0xFFD32F2F));
    });
  });

  group('PlayerColors', () {
    test('supports the required range of players', () {
      expect(PlayerColors.minPlayers, 2);
      expect(PlayerColors.maxPlayers, 10);
    });

    test('palette has exactly one color per supported player, all distinct',
        () {
      expect(PlayerColors.palette.length, PlayerColors.maxPlayers);
      expect(PlayerColors.palette.toSet().length, PlayerColors.palette.length);
    });

    test('nextAvailable returns the first color not already in use', () {
      expect(
        PlayerColors.nextAvailable(const {}),
        PlayerColors.palette[0],
      );
      expect(
        PlayerColors.nextAvailable({PlayerColors.palette[0]}),
        PlayerColors.palette[1],
      );
    });

    test('nextAvailable reuses a color once it is freed', () {
      final freed = {PlayerColors.palette[0], PlayerColors.palette[2]};
      expect(PlayerColors.nextAvailable(freed), PlayerColors.palette[1]);
    });

    test('nextAvailable throws when every color is in use', () {
      expect(
        () => PlayerColors.nextAvailable(PlayerColors.palette.toSet()),
        throwsStateError,
      );
    });
  });
}
