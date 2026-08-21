import 'game_catalog.dart';

/// Returns games sorted by descending play count.
///
/// Games with equal play counts preserve their original catalog order
/// (stable sort). Only available games can have non-zero counts; Coming
/// Soon games always start at 0.
List<GameEntry> sortedByPlayCount(
  List<GameEntry> catalog,
  Map<String, int> counts,
) {
  // Build an index map for catalog-order tiebreaking.
  final indexMap = <String, int>{};
  for (var i = 0; i < catalog.length; i++) {
    indexMap[catalog[i].id] = i;
  }

  final sorted = List<GameEntry>.from(catalog);
  sorted.sort((a, b) {
    final aCount = counts[a.id] ?? 0;
    final bCount = counts[b.id] ?? 0;
    final cmp = bCount.compareTo(aCount); // descending
    if (cmp != 0) return cmp;
    // Tiebreak by catalog order.
    return (indexMap[a.id] ?? 0).compareTo(indexMap[b.id] ?? 0);
  });
  return sorted;
}
