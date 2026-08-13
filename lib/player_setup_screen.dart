import 'package:flutter/material.dart';

import 'game_start_screen.dart';
import 'game_state.dart';
import 'multiplayer/driver.dart';
import 'player.dart';
import 'player_colors.dart';

/// Screen where players are configured before a game begins.
///
/// A single phone is passed around, so setup is intentionally simple:
/// type a name, press Add, repeat. Removing a player frees their color for
/// reuse. Start Game hands the configured players off to the game flow.
class PlayerSetupScreen extends StatefulWidget {
  const PlayerSetupScreen({super.key});

  @override
  State<PlayerSetupScreen> createState() => _PlayerSetupScreenState();
}

class _PlayerSetupScreenState extends State<PlayerSetupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final List<Player> _players = [];

  /// Validation message for the name field, or null when the input is valid.
  String? _nameError;

  /// Monotonic counter backing player ids within this session.
  int _nextPlayerId = 0;

  bool get _canAddPlayer => _players.length < PlayerColors.maxPlayers;

  bool get _canStartGame => _players.length >= PlayerColors.minPlayers;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _handleNameChanged(String _) {
    if (_nameError != null) {
      setState(() => _nameError = null);
    }
  }

  void _addPlayer() {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      setState(() => _nameError = 'Enter a name to add a player.');
      return;
    }

    final isDuplicate = _players.any(
      (player) => player.name.toLowerCase() == name.toLowerCase(),
    );
    if (isDuplicate) {
      setState(() => _nameError = '"$name" is already in the game.');
      return;
    }

    if (!_canAddPlayer) {
      // Unreachable while the field is disabled at the max; kept as a guard.
      return;
    }

    final usedColors = _players.map((player) => player.color).toSet();
    setState(() {
      _players.add(
        Player(
          id: 'player-${_nextPlayerId++}',
          name: name,
          color: PlayerColors.nextAvailable(usedColors),
        ),
      );
      _nameController.clear();
      _nameError = null;
    });
  }

  void _removePlayer(Player player) {
    setState(() => _players.remove(player));
  }

  void _startGame() {
    if (!_canStartGame) {
      return;
    }
    final game = GameState(players: List.unmodifiable(_players));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameStartScreen(driver: LocalDriver(game)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Player Setup')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'Turtle King',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Players', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Text(
                    '${_players.length} / ${PlayerColors.maxPlayers}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Add between ${PlayerColors.minPlayers} and '
                '${PlayerColors.maxPlayers} players, then start the game.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _players.isEmpty
                    ? Center(
                        child: Text(
                          'No players yet.\nAdd your first player below.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _players.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final player = _players[index];
                          return _PlayerTile(
                            player: player,
                            onRemove: () => _removePlayer(player),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              if (!_canAddPlayer) ...[
                Text(
                  'Maximum of ${PlayerColors.maxPlayers} players reached.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      enabled: _canAddPlayer,
                      onChanged: _handleNameChanged,
                      onSubmitted: (_) => _addPlayer(),
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Player name',
                        hintText: 'e.g. "Caleb"',
                        errorText: _nameError,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _canAddPlayer ? _addPlayer : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _canStartGame ? _startGame : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: theme.textTheme.titleMedium,
                ),
                child: const Text('Start Game'),
              ),
              if (!_canStartGame) ...[
                const SizedBox(height: 8),
                Text(
                  'Add at least ${PlayerColors.minPlayers} players to '
                  'start the game.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single row in the player list: color swatch, name, remove action.
class _PlayerTile extends StatelessWidget {
  const _PlayerTile({required this.player, required this.onRemove});

  final Player player;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: player.color),
      title: Text(player.name),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Remove ${player.name}',
        onPressed: onRemove,
      ),
    );
  }
}
