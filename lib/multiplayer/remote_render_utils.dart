import '../card.dart';
import '../game_state.dart';
import 'private_state.dart';

/// Converts a `CupSize.name` string from the public state back to the local
/// enum for rendering. Falls back to [CupSize.normal] for unknown values so
/// a future protocol addition can never break rendering.
CupSize cupSizeFromName(String name) => switch (name) {
  'normal' => CupSize.normal,
  'large' => CupSize.large,
  'extraLarge' => CupSize.extraLarge,
  _ => CupSize.normal,
};

/// Converts the client's own authorized [PrivateCard] back to a local
/// [Card] for display. This is the ONLY place a card identity is turned
/// into a renderable card on the remote side, and it is always the client's
/// own card.
Card cardFromPrivate(PrivateCard private) {
  final suit = Suit.values.where((s) => s.name == private.suit).firstOrNull;
  final rank = Rank.values.where((r) => r.name == private.rank).firstOrNull;
  return Card(suit: suit ?? Suit.spades, rank: rank ?? Rank.ace);
}
