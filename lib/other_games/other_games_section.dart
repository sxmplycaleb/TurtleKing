import 'package:flutter/material.dart';

import 'game_catalog.dart';
import 'game_preview_screen.dart';
import 'game_ranking.dart';

/// Collapsible "OTHER GAMES" section on the home screen.
///
/// Collapsed by default. When expanded, shows games sorted by descending play
/// count, with catalog order as tiebreaker. Tapping a card opens
/// [GamePreviewScreen] — no gameplay is launched.
///
/// Pass [playCounts] to provide persisted play-count data. When all counts
/// are zero, games appear in catalog order.
class OtherGamesSection extends StatefulWidget {
  const OtherGamesSection({super.key, this.playCounts = const {}});

  /// Per-game play counts keyed by [GameEntry.id].
  final Map<String, int> playCounts;

  @override
  State<OtherGamesSection> createState() => _OtherGamesSectionState();
}

class _OtherGamesSectionState extends State<OtherGamesSection>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = sortedByPlayCount(gameCatalog, widget.playCounts);

    // Determine if there's a meaningful play-count leader.
    final maxCount = sorted.isEmpty
        ? 0
        : (widget.playCounts[sorted.first.id] ?? 0);
    final hasPlays = maxCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header — tap to expand/collapse
        InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Text(
                  'OTHER GAMES',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expandable game list — only builds children when expanded
        SizeTransition(
          sizeFactor: _animation,
          alignment: Alignment.centerLeft,
          child: _expanded
              ? Column(
                  children: [
                    for (final game in sorted) ...[
                      _GameCard(
                        game: game,
                        playCount: widget.playCounts[game.id] ?? 0,
                        showMostPlayed: hasPlays && game.id == sorted.first.id,
                      ),
                      if (game != sorted.last) const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 8),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// A full-width card for a game in the expanded list.
class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.game,
    required this.playCount,
    required this.showMostPlayed,
  });

  final GameEntry game;
  final int playCount;
  final bool showMostPlayed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => GamePreviewScreen(game: game),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Image.asset(
                game.artworkAsset,
                width: 40,
                height: 40,
                fit: BoxFit.contain,
                semanticLabel: '${game.name} artwork',
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (showMostPlayed && playCount > 0) ...[
                      Text(
                        'MOST PLAYED',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '$playCount ${playCount == 1 ? 'PLAY' : 'PLAYS'}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ] else if (!game.isAvailable) ...[
                      Text(
                        'COMING SOON',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
