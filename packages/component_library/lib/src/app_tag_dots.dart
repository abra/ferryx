import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Finder's tag colours by Finder's own numbering (1 grey, 2 green,
/// 3 purple, 4 blue, 5 yellow, 6 red, 7 orange; 0 is no colour), in the
/// system colours of macOS for each brightness, as Finder draws them.
abstract final class AppTagColors {
  static const _light = [
    Color(0x00000000),
    Color(0xFF8E8E93),
    Color(0xFF34C759),
    Color(0xFFAF52DE),
    Color(0xFF007AFF),
    Color(0xFFFFCC00),
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
  ];
  static const _dark = [
    Color(0x00000000),
    Color(0xFF98989D),
    Color(0xFF30D158),
    Color(0xFFBF5AF2),
    Color(0xFF0A84FF),
    Color(0xFFFFD60A),
    Color(0xFFFF453A),
    Color(0xFFFF9F0A),
  ];

  /// The colours in the order Finder's tag menu lists them: red, orange,
  /// yellow, green, blue, purple, grey.
  static const menuOrder = [6, 7, 5, 2, 4, 3, 1];

  /// The colour [color] (Finder's number) in this theme's brightness.
  static Color of(BuildContext context, int color) =>
      (Theme.of(context).brightness == Brightness.dark ? _dark : _light)[color
          .clamp(0, 7)];
}

/// A file's tag colours as Finder shows them after a name: small dots,
/// each over the one before by part of its width, ringed with [ring] (the
/// row's own background) so they stay apart; three at most.
class AppTagDots extends StatelessWidget {
  const AppTagDots({
    required this.colors,
    required this.size,
    this.ring,
    super.key,
  });

  /// Finder colour numbers, 1 to 7, in the tags' order.
  final List<int> colors;

  /// The background the dots stand on, drawn round each to keep them
  /// apart; none for a lone dot on a plain background (a menu's).
  final Color? ring;

  /// A dot's diameter, its ring included.
  final double size;

  /// Dots shown at most: Finder's own limit.
  static const int most = 3;

  /// How far each dot is from the one before, as a part of its size.
  static const double step = 0.6;

  /// The width [count] dots of [size] take.
  static double widthOf(int count, double size) =>
      count <= 0 ? 0 : size + (math.min(count, most) - 1) * size * step;

  @override
  Widget build(BuildContext context) {
    final shown = colors.take(most).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return CustomPaint(
      size: Size(widthOf(shown.length, size), size),
      painter: _DotsPainter(
        colors: [for (final c in shown) AppTagColors.of(context, c)],
        ring: ring,
        size: size,
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter({
    required this.colors,
    required this.ring,
    required this.size,
  });

  final List<Color> colors;
  final Color? ring;
  final double size;

  @override
  void paint(Canvas canvas, Size area) {
    final radius = size / 2;
    final ring = this.ring;
    for (var i = 0; i < colors.length; i++) {
      final center = Offset(
        radius + i * size * AppTagDots.step,
        area.height / 2,
      );
      if (ring != null) {
        canvas.drawCircle(center, radius, Paint()..color = ring);
      }
      canvas.drawCircle(
        center,
        ring == null ? radius : radius - 1,
        Paint()..color = colors[i],
      );
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.ring != ring || old.size != size || !_same(old.colors, colors);

  static bool _same(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
