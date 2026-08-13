import '../card.dart';
import '../game_state.dart';
import '../player.dart';
import 'json_util.dart';

/// The single card identity the protocol may carry: one rule-authorized
/// card, bound to exactly one recipient player and one round.
///
/// This is the ONLY place card identities may cross the network. It is
/// deliberately narrow:
///
/// * it holds exactly **one** [PrivateCard] — there is no list, no second
///   card, no hand;
/// * it is bound to a single `recipientPlayerId`, so a message built for
///   player A can never carry player B's card by construction;
/// * the normal factory ([PrivateStateView.forVisibleCard]) reads through
///   the public `GameState.visibleCardOf` — the getter the rules authorize —
///   so the hidden second card and every other player's cards are simply
///   unreachable through this API.
class PrivateStateView {
  const PrivateStateView({
    required this.recipientPlayerId,
    required this.round,
    required this.card,
  });

  /// Builds the authorized private view of [recipient]'s visible card in the
  /// current round of [game].
  ///
  /// Uses only the public `visibleCardOf` getter, which returns exactly one
  /// card: the recipient's own first card. `GameState.handOf` (which would
  /// expose the hidden second card) is never touched by this layer.
  factory PrivateStateView.forVisibleCard(GameState game, Player recipient) {
    return PrivateStateView(
      recipientPlayerId: recipient.id,
      round: game.roundNumber,
      card: PrivateCard.fromCard(game.visibleCardOf(recipient)),
    );
  }

  final String recipientPlayerId;
  final int round;
  final PrivateCard card;

  Map<String, Object?> toJson() => {
    'recipientPlayerId': recipientPlayerId,
    'round': round,
    'card': card.toJson(),
  };

  factory PrivateStateView.fromJson(Object? value) {
    final map = requireMap(value, 'private state');
    return PrivateStateView(
      recipientPlayerId: requireString(
        map['recipientPlayerId'],
        'private state.recipientPlayerId',
      ),
      round: requireInt(map['round'], 'private state.round'),
      card: PrivateCard.fromJson(map['card']),
    );
  }
}

/// One serialized card identity (suit + rank names).
///
/// Exists only inside [PrivateStateView]; the public state never contains it.
class PrivateCard {
  const PrivateCard({required this.suit, required this.rank});

  factory PrivateCard.fromCard(Card card) =>
      PrivateCard(suit: card.suit.name, rank: card.rank.name);

  final String suit;
  final String rank;

  Map<String, Object?> toJson() => {'suit': suit, 'rank': rank};

  factory PrivateCard.fromJson(Object? value) {
    final map = requireMap(value, 'card');
    return PrivateCard(
      suit: requireString(map['suit'], 'card.suit'),
      rank: requireString(map['rank'], 'card.rank'),
    );
  }
}
