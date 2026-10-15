import 'package:flutter/material.dart';

/// Su schermi larghi (iPad, Mac, desktop) tiene il contenuto in una colonna
/// centrata leggibile invece di stirarlo a tutta larghezza.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 720});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
