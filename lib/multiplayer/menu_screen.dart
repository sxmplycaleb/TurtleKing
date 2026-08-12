import 'package:flutter/material.dart';

import 'host_lobby_screen.dart';
import 'join_lobby_screen.dart';

/// The Phase 18 multiplayer entry point: choose to host a LAN session or
/// join one. Purely navigation — no network resources are created here.
class MultiplayerMenuScreen extends StatelessWidget {
  const MultiplayerMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Multiplayer')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'Play Turtle King with friends on separate devices. '
                'Everyone must be on the same Wi-Fi network.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HostLobbyScreen(),
                  ),
                ),
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Host Game'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const JoinLobbyScreen(),
                  ),
                ),
                icon: const Icon(Icons.search),
                label: const Text('Join Game'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
