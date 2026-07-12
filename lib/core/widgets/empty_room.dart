import 'package:flutter/material.dart';

/// The illustration for "there is nothing here": a doorway opening onto an
/// empty, dark room — a dead end, not just a blank glyph. Used where scrolling
/// further will never turn anything up, like a playlist or group with nothing
/// added to it yet.
class EmptyRoom extends StatelessWidget {
  const EmptyRoom({super.key, this.size = 160});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _EmptyRoomPainter(
          wall: scheme.surfaceContainerHigh,
          floor: scheme.surfaceContainer,
          frame: scheme.outlineVariant,
          accent: scheme.primary,
        ),
      ),
    );
  }
}

class _EmptyRoomPainter extends CustomPainter {
  _EmptyRoomPainter({
    required this.wall,
    required this.floor,
    required this.frame,
    required this.accent,
  });

  final Color wall;
  final Color floor;
  final Color frame;
  final Color accent;

  /// The doorway is always this dark, in both themes — actual darkness does
  /// not lighten because the app switched to light mode.
  static const _void = Color(0xFF08090C);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Back wall.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h * 0.82),
        const Radius.circular(18),
      ),
      Paint()..color = wall,
    );

    // Floor strip, meeting the wall in a hard edge — the room ends here.
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.80, w, h * 0.20),
      Paint()..color = floor,
    );

    // The doorway itself: an arch fading into darkness, so it reads as depth
    // rather than a flat cutout pasted on the wall.
    final doorWidth = w * 0.38;
    final doorHeight = h * 0.58;
    final doorRect = Rect.fromLTWH(
      (w - doorWidth) / 2,
      h * 0.82 - doorHeight,
      doorWidth,
      doorHeight,
    );
    final doorShape = RRect.fromRectAndCorners(
      doorRect,
      topLeft: const Radius.circular(46),
      topRight: const Radius.circular(46),
    );

    canvas.drawRRect(
      doorShape,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.topCenter,
          radius: 1.0,
          colors: [_void.withValues(alpha: 0.65), _void],
        ).createShader(doorRect),
    );
    canvas.drawRRect(
      doorShape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = frame,
    );

    // A single point of light, far off in the dark — empty, but not quite
    // nothing.
    canvas.drawCircle(
      Offset(w / 2, doorRect.top + doorHeight * 0.4),
      2.6,
      Paint()..color = accent.withValues(alpha: 0.6),
    );

    // The shadow the doorway casts onto the floor.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, h * 0.87),
        width: doorWidth * 1.2,
        height: h * 0.05,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(covariant _EmptyRoomPainter oldDelegate) {
    return oldDelegate.wall != wall ||
        oldDelegate.floor != floor ||
        oldDelegate.frame != frame ||
        oldDelegate.accent != accent;
  }
}
