import 'dart:async';

import 'package:flutter/material.dart' hide Card;

import '../card_widgets.dart';
import '../game_table.dart';
import '../theme.dart';
import 'remote_driver.dart';
import 'remote_game_controller.dart';
import 'remote_game_view.dart';
import 'remote_render_utils.dart';

/// The gameplay screen for a device-to-device remote game.
///
/// Driven entirely by a [RemoteGameController] (host or client) and renders
/// only [RemoteGameView] — sanitized public state plus the device player's
/// own authorized card. It shows the full set of connection/turn states:
/// connecting, joining, in lobby (waiting for host), your turn, waiting for
/// another player, reconnecting, resyncing, connection failed, host/session
/// ended, and action rejections.
///
/// No gameplay rules live here — every action is sent to the controller and
/// validated by the authoritative host.
class RemoteGameScreen extends StatefulWidget {
  const RemoteGameScreen({super.key, required this.controller});

  final RemoteGameController controller;

  @override
  State<RemoteGameScreen> createState() => _RemoteGameScreenState();
}

class _RemoteGameScreenState extends State<RemoteGameScreen> {
  StreamSubscription<RemoteGameEvent>? _sub;
  RemoteGameStatus _status = RemoteGameStatus.connecting;
  String? _rejection;
  bool _leaving = false;

  RemoteGameController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _status = _controller.status;
    _sub = _controller.events.listen(_onEvent);
    // Hosts start immediately; clients wait for GAME_START from the host.
    if (_controller.isHost) {
      final host = _controller;
      if (host is HostRemoteController) {
        host.start();
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onEvent(RemoteGameEvent event) {
    if (!mounted) return;
    setState(() {
      _status = event.status;
      if (event.rejection != null) _rejection = event.rejection;
    });
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await _controller.leave();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Remote Game')),
      body: SafeArea(child: _body(theme)),
    );
  }

  Widget _body(ThemeData theme) {
    switch (_status) {
      case RemoteGameStatus.connecting:
        return _statusView(
          theme,
          icon: Icons.wifi_tethering,
          title: 'Connecting…',
          subtitle: 'Establishing the session with the host.',
        );
      case RemoteGameStatus.inLobby:
        return _statusView(
          theme,
          icon: Icons.hourglass_top,
          title: 'Waiting for the host',
          subtitle: 'The host will start the game when everyone is ready.',
          child: _rosterList(theme),
        );
      case RemoteGameStatus.reconnecting:
        return _statusView(
          theme,
          icon: Icons.sync,
          title: 'Reconnecting…',
          subtitle: 'The connection was lost. Trying to rejoin the game.',
        );
      case RemoteGameStatus.resyncing:
        return _statusView(
          theme,
          icon: Icons.sync,
          title: 'Reconnected',
          subtitle: 'Asking the host for the current game state…',
        );
      case RemoteGameStatus.sessionEnded:
        return _statusView(
          theme,
          icon: Icons.flag,
          title: 'Session ended',
          subtitle: 'The host ended the session.',
          child: _backButton(theme),
        );
      case RemoteGameStatus.connectionFailed:
        return _statusView(
          theme,
          icon: Icons.wifi_off,
          title: 'Connection failed',
          subtitle:
              'Could not reach the host. Check the connection and try again.',
          child: _retryButton(theme),
        );
      case RemoteGameStatus.idle:
        return _statusView(
          theme,
          icon: Icons.info,
          title: 'Not connected',
          subtitle: 'Join a game to start playing.',
        );
      case RemoteGameStatus.playing:
        return _gameView(theme);
    }
  }

  Widget _statusView(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? child,
  }) {
    final style = GameTableStyle.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 56, color: style.accentText),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: style.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: style.textSecondary,
              height: 1.4,
            ),
          ),
          if (child != null) ...[const SizedBox(height: 24), child],
        ],
      ),
    );
  }

  Widget _backButton(ThemeData theme) {
    return FilledButton.icon(
      onPressed: _leave,
      icon: const Icon(Icons.home),
      label: const Text('Back to Home'),
    );
  }

  Widget _retryButton(ThemeData theme) {
    final controller = _controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () async {
            final ok = await controller.reconnect();
            if (ok && mounted) {
              setState(() => _status = RemoteGameStatus.playing);
            }
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Try Again'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _leave, child: const Text('Back to Home')),
      ],
    );
  }

  Widget _rosterList(ThemeData theme) {
    final style = GameTableStyle.of(context);
    final view = _controller.view;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Players (${view.players.length})',
          style: theme.textTheme.titleMedium?.copyWith(
            color: style.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        for (final player in view.players)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Color(player.color),
              child: Text(
                player.name.characters.first,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(player.name),
            trailing: player.id == view.selfPlayerId
                ? Text('you', style: theme.textTheme.bodySmall)
                : null,
          ),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Active game
  // -------------------------------------------------------------------

  Widget _gameView(ThemeData theme) {
    final style = GameTableStyle.of(context);
    final view = _controller.view;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_rejection != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: style.danger.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: style.danger),
              ),
              child: Text(
                _rejection!,
                textAlign: TextAlign.center,
                style: TextStyle(color: style.danger),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _header(theme, view),
          const SizedBox(height: 20),
          ..._phaseContent(theme, view),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, RemoteGameView view) {
    final style = GameTableStyle.of(context);
    final current = view.currentPlayer;
    final String turnText;
    if (view.gameComplete) {
      turnText = 'Game over';
    } else if (view.roundComplete) {
      turnText = 'Round ${view.roundNumber} complete';
    } else if (view.pouringStarted) {
      turnText = view.isMyTurn
          ? 'Your turn — pour!'
          : 'Waiting for ${current?.name ?? '…'}';
    } else if (view.allPlayersViewed) {
      turnText = 'Pass to ${current?.name ?? 'the next player'}';
    } else if (view.isMyTurn) {
      turnText = view.currentPlayerRevealed ? 'Your card' : 'Your turn to look';
    } else {
      turnText = 'Waiting for ${current?.name ?? '…'}';
    }
    return Column(
      children: [
        _roundBadge(theme, view),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: current == null
                  ? style.textSecondary
                  : Color(current.color),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                turnText,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: style.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${view.players.length} players · '
          'Round ${view.roundNumber} · '
          '${view.lifetimeDrinks.values.fold<int>(0, (a, b) => a + b)} total drinks',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: style.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _roundBadge(ThemeData theme, RemoteGameView view) {
    final style = GameTableStyle.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: style.chipBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: style.chipBorder),
      ),
      child: Text(
        'Round ${view.roundNumber}',
        style: TextStyle(
          color: style.accentText,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  List<Widget> _phaseContent(ThemeData theme, RemoteGameView view) {
    final style = GameTableStyle.of(context);
    final controller = _controller;

    if (view.gameComplete) {
      return [_gameOverContent(theme, view)];
    }
    if (view.roundComplete) {
      return [_roundCompleteContent(theme, view)];
    }
    if (view.pouringStarted) {
      return [
        Center(
          child: TurtleKingCup(
            size: cupSizeFromName(view.cupSize),
            diameter: 54,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Water is being poured — round ${view.roundNumber}. '
          'If your other card feels too small, '
          'shout YAMADA — or hold out.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: style.textPrimary,
            height: 1.4,
          ),
        ),
        if (view.isMyTurn && view.myCard != null) ...[
          const SizedBox(height: 12),
          Text(
            'Your visible card (private):',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              color: style.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CardFace(card: cardFromPrivate(view.myCard!)),
                const SizedBox(width: 14),
                const CardBack(),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _infoChip(
            theme,
            'Drinks: ${view.myLifetimeDrinks ?? 0} '
            '(${view.publicState.eliminationThreshold} drinks eliminate)',
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: controller.callYamada,
            style: FilledButton.styleFrom(
              backgroundColor: style.danger,
              foregroundColor: style.onDanger,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('YAMADA!', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: controller.holdOut,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Hold out'),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'Waiting for ${view.currentPlayer?.name ?? 'the next player'} '
              'to decide.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: style.textSecondary,
              ),
            ),
          ),
      ];
    }
    if (view.allPlayersViewed) {
      return [
        const SizedBox(height: 24),
        Icon(Icons.phone_iphone, color: style.textPrimary, size: 40),
        const SizedBox(height: 16),
        Text(
          'Everyone has looked at their card. Pouring is about to begin.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: style.textPrimary),
        ),
      ];
    }
    // Viewing phase.
    if (view.isMyTurn) {
      return [
        if (!view.currentPlayerRevealed) ...[
          const SizedBox(height: 8),
          Text(
            'This is the only card you may look at. Memorize it, then pass.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: style.textPrimary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: controller.revealCurrentPlayer,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Reveal My Card'),
          ),
        ] else ...[
          const SizedBox(height: 8),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (view.myCard != null)
                  CardFace(card: cardFromPrivate(view.myCard!))
                else
                  const CardBack(),
                const SizedBox(width: 14),
                const CardBack(),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: controller.passToNextPlayer,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Pass to Next Player'),
          ),
        ],
      ];
    }
    return [
      const SizedBox(height: 24),
      Text(
        'Waiting for ${view.currentPlayer?.name ?? 'the next player'} to '
        'look at their card.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge?.copyWith(color: style.textSecondary),
      ),
    ];
  }

  Widget _roundCompleteContent(ThemeData theme, RemoteGameView view) {
    final style = GameTableStyle.of(context);
    final result = view.roundResults.isNotEmpty ? view.roundResults.last : null;
    final yamadaCalled = result?.calledYamada.values.any((c) => c) ?? false;
    final controller = _controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Round ${view.roundNumber} complete',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: style.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (yamadaCalled) ...[
          Text(
            'YAMADA was called — cards revealed!',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: style.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The YAMADA caller takes 0 or 1 shot based on whether they '
            'had the smallest hand.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: style.textSecondary,
            ),
          ),
        ] else ...[
          Text(
            'Everyone held out — hands were revealed!',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: style.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (result != null)
            for (final id in result.smallestHands)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${_nameFor(view, id)} drank ${result.drinks[id] ?? 1} '
                  'cup${(result.drinks[id] ?? 1) == 1 ? '' : 's'} '
                  '(smallest hand)',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: style.accentText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
        ],
        const SizedBox(height: 16),
        Text(
          'Drinks this round:',
          style: theme.textTheme.titleSmall?.copyWith(
            color: style.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        for (final player in view.players)
          if ((view.roundDrinks[player.id] ?? 0) > 0)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: CircleAvatar(
                radius: 12,
                backgroundColor: Color(player.color),
              ),
              title: Text(player.name),
              trailing: Text('${view.roundDrinks[player.id]} shot(s)'),
            ),
        const SizedBox(height: 16),
        if (view.canStartNextRound)
          FilledButton(
            onPressed: controller.startNextRound,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Next Round'),
          )
        else
          Text(
            'Waiting for the host to start the next round.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: style.textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _gameOverContent(ThemeData theme, RemoteGameView view) {
    final style = GameTableStyle.of(context);
    final result = view.finalResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '👑 ${view.iWon ? 'You are the Turtle King!' : 'Game over'}',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: style.accentText,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (result != null)
          Text(
            'Turtle King${result.turtleKings.length == 1 ? '' : 's'}: '
            '${result.turtleKings.map((id) => _nameFor(view, id)).join(', ')}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: style.textPrimary,
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Final drinks:',
          style: theme.textTheme.titleSmall?.copyWith(
            color: style.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        for (final player in view.players)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: Color(player.color),
            ),
            title: Text(player.name),
            trailing: Text(
              '${view.lifetimeDrinks[player.id] ?? 0} '
              '(${view.publicState.eliminationThreshold} eliminates)',
            ),
          ),
        const SizedBox(height: 24),
        _backButton(theme),
      ],
    );
  }

  Widget _infoChip(ThemeData theme, String text) {
    final style = GameTableStyle.of(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: style.chipBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: style.textSecondary,
          ),
        ),
      ),
    );
  }

  String _nameFor(RemoteGameView view, String playerId) {
    return view.players.where((p) => p.id == playerId).firstOrNull?.name ??
        playerId;
  }
}
