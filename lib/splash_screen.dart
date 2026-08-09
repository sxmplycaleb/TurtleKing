import 'dart:async';

import 'package:flutter/material.dart';

import 'home_screen.dart';

/// Branded launch screen shown briefly while the app starts.
///
/// Displays the full Turtle King artwork (emblem + TURTLE/KING banner) on the
/// navy brand background, then fades into the home screen. Purely
/// presentational: no game state is created, started, or mutated here.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.duration = const Duration(milliseconds: 1200),
  });

  /// How long the splash stays visible before transitioning to home.
  final Duration duration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, _goHome);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const HomeScreen(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B263C),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Image.asset(
              'assets/branding/turtle_king_splash.png',
              fit: BoxFit.contain,
              semanticLabel: 'Turtle King',
            ),
          ),
        ),
      ),
    );
  }
}
