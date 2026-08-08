import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'theme.dart';

void main() {
  runApp(const TurtleKingApp());
}

/// Root widget for the Turtle King app.
class TurtleKingApp extends StatelessWidget {
  const TurtleKingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Turtle King',
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}
