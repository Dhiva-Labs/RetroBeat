import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models/visualizer_style.dart';
import '../../../data/services/visualizer_service.dart';

/// Everything a painter needs: the frame, the palette, and a clock.
class VisualizerPaint {
  const VisualizerPaint({
    required this.frame,
    required this.primary,
    required this.secondary,
    required this.time,
  });

  final VisualizerFrame frame;
  final Color primary;
  final Color secondary;

  /// Seconds since the visualiser started, for anything that rotates or drifts.
  final double time;

  Color blend(double t) => Color.lerp(primary, secondary, t.clamp(0, 1))!;
}

/// Dispatches to the painter for [style].
CustomPainter painterFor(VisualizerStyle style, VisualizerPaint p) {
  return switch (style) {
    VisualizerStyle.ambience => _AmbiencePainter(p),
    VisualizerStyle.alchemy => _AlchemyPainter(p),
    VisualizerStyle.plenty => _PlentyPainter(p),
    VisualizerStyle.bars => _BarsPainter(p),
    VisualizerStyle.oceanMist => _OceanMistPainter(p),
    VisualizerStyle.scope => _ScopePainter(p),
    VisualizerStyle.battery => _BatteryPainter(p),
    VisualizerStyle.fireStorm => _FireStormPainter(p),
  };
}

/// How much of the previous frame survives into this one.
///
/// This is the whole trick behind the flowing styles: a value near 1 leaves long
/// liquid smears, a lower one leaves crisp shapes. The bar styles want no trail
/// at all, or the meter would never fall.
double trailPersistenceFor(VisualizerStyle style) {
  return switch (style) {
    VisualizerStyle.ambience => 0.90,
    VisualizerStyle.alchemy => 0.94,
    VisualizerStyle.plenty => 0.92,
    _ => 0.0,
  };
}

abstract class _VizPainter extends CustomPainter {
  const _VizPainter(this.p);

  final VisualizerPaint p;

  // The frame changes every tick, so there is never a case where skipping the
  // repaint would be correct.
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// The classic spectrum: one bar per band, hot at the peaks.
class _BarsPainter extends _VizPainter {
  const _BarsPainter(super.p);

  @override
  void paint(Canvas canvas, Size size) {
    final bands = p.frame.bands;
    if (bands.isEmpty) return;

    final slot = size.width / bands.length;
    final barWidth = slot * 0.62;

    for (var i = 0; i < bands.length; i++) {
      final level = bands[i].clamp(0.0, 1.0);
      final barHeight = math.max(2.0, level * size.height);
      final left = i * slot + (slot - barWidth) / 2;
      final top = size.height - barHeight;
      final rect = Rect.fromLTWH(left, top, barWidth, barHeight);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [p.primary, p.blend(level)],
          ).createShader(rect),
      );
    }
  }
}

/// Ocean Mist: the spectrum mirrored about the centre line, with a slow swell
/// riding through it.
class _OceanMistPainter extends _VizPainter {
  const _OceanMistPainter(super.p);

  @override
  void paint(Canvas canvas, Size size) {
    final bands = p.frame.bands;
    if (bands.isEmpty) return;

    final mid = size.height / 2;
    final slot = size.width / bands.length;
    final barWidth = slot * 0.55;

    for (var i = 0; i < bands.length; i++) {
      final level = bands[i].clamp(0.0, 1.0);
      // The swell keeps the mirrored halves from being a dead reflection.
      final swell =
          0.12 * math.sin((i / bands.length) * 4 * math.pi + p.time * 1.6);
      final half = math.max(1.5, (level + swell).clamp(0.0, 1.0) * mid * 0.92);
      final left = i * slot + (slot - barWidth) / 2;
      final rect = Rect.fromLTRB(left, mid - half, left + barWidth, mid + half);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              p.blend(level).withValues(alpha: 0.95),
              p.primary.withValues(alpha: 0.35),
              p.blend(level).withValues(alpha: 0.95),
            ],
          ).createShader(rect),
      );
    }

    // The mist: a soft band across the middle.
    canvas.drawRect(
      Rect.fromLTWH(0, mid - 1, size.width, 2),
      Paint()..color = p.secondary.withValues(alpha: 0.25),
    );
  }
}

/// Scope: an oscilloscope trace of the waveform itself.
class _ScopePainter extends _VizPainter {
  const _ScopePainter(super.p);

  @override
  void paint(Canvas canvas, Size size) {
    final wave = p.frame.wave;
    if (wave.length < 2) return;

    final mid = size.height / 2;
    final dx = size.width / (wave.length - 1);

    final path = Path()..moveTo(0, mid - wave.first * mid * 0.9);
    for (var i = 1; i < wave.length; i++) {
      path.lineTo(i * dx, mid - wave[i] * mid * 0.9);
    }

    // Phosphor: a wide soft pass under a bright thin one, which is what makes a
    // CRT trace look lit rather than drawn.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = p.primary.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = p.secondary,
    );

    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()..color = p.primary.withValues(alpha: 0.12),
    );
  }
}

/// Battery: spikes radiating from the centre, turning slowly. The one everyone
/// remembers.
class _BatteryPainter extends _VizPainter {
  const _BatteryPainter(super.p);

  @override
  void paint(Canvas canvas, Size size) {
    final bands = p.frame.bands;
    if (bands.isEmpty) return;

    final centre = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2;
    final inner = maxRadius * 0.22;

    // Mirror the spectrum around the circle so the star is symmetric.
    final spokes = bands.length * 2;

    for (var i = 0; i < spokes; i++) {
      final band = i < bands.length ? bands[i] : bands[spokes - 1 - i];
      final level = band.clamp(0.0, 1.0);
      final angle = (i / spokes) * 2 * math.pi + p.time * 0.35;
      final length = inner + level * (maxRadius - inner) * 0.95;

      final from = centre + Offset(math.cos(angle), math.sin(angle)) * inner;
      final to = centre + Offset(math.cos(angle), math.sin(angle)) * length;

      canvas.drawLine(
        from,
        to,
        Paint()
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = p.blend(level).withValues(alpha: 0.55 + level * 0.45),
      );
    }

    // The core pulses with the bass, which is where the energy actually is.
    final bass = bands.take(3).fold<double>(0, (a, b) => a + b) / 3;
    canvas.drawCircle(
      centre,
      inner * (0.6 + bass * 0.6),
      Paint()
        ..color = p.secondary.withValues(alpha: 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }
}

/// Ambience: sheets of plasma sliding over each other.
///
/// Nothing here is a bar. Each frame lays down a few soft, warped bands of
/// light; the trail buffer keeps the previous ones, so what you see is the wake
/// of a field in motion rather than a redrawn chart. Loudness pushes the sheets
/// apart and brightens them; it never resets them.
class _AmbiencePainter extends _VizPainter {
  const _AmbiencePainter(super.p);

  @override
  void paint(Canvas canvas, Size size) {
    final bands = p.frame.bands;
    if (bands.isEmpty) return;

    final energy = bands.fold<double>(0, (a, b) => a + b) / bands.length;
    final bass = bands.take(4).fold<double>(0, (a, b) => a + b) / 4;

    canvas.saveLayer(Offset.zero & size, Paint());

    const sheets = 6;
    for (var s = 0; s < sheets; s++) {
      final phase = p.time * (0.26 + s * 0.07) + s * 2.1;
      final amplitude = size.height * (0.11 + bass * 0.20);
      // Kept as a fraction of the *width*: tying it to height made the ribbons
      // as thick as the screen once this went full-bleed, and they blurred into
      // an undifferentiated fog.
      final thickness = size.width * (0.035 + energy * 0.055);

      // A warped ribbon spanning the width; two sines of different periods keep
      // it from ever looking periodic.
      final path = Path();
      const steps = 48;
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = t * size.width;
        final y = size.height * (0.5 + 0.26 * math.sin(phase * 0.7 + s)) +
            math.sin(t * 3.1 * math.pi + phase) * amplitude +
            math.sin(t * 7.3 * math.pi - phase * 1.4) * amplitude * 0.45;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus
          ..color =
              p.blend(s / (sheets - 1)).withValues(alpha: 0.09 + energy * 0.16)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, thickness * 0.42),
      );
    }

    canvas.restore();
  }
}

/// Alchemy: ribbons winding around one another, leaving a long wake.
///
/// A Lissajous pair whose frequencies drift with the music, stroked as a bright
/// thin line. On its own a single frame is just a curve — it is the trail that
/// turns it into the woven, glassy knot WMP was known for.
class _AlchemyPainter extends _VizPainter {
  const _AlchemyPainter(super.p);

  @override
  void paint(Canvas canvas, Size size) {
    final bands = p.frame.bands;
    if (bands.isEmpty) return;

    final energy = bands.fold<double>(0, (a, b) => a + b) / bands.length;
    final mid = bands.length ~/ 2;
    final treble =
        bands.skip(mid).fold<double>(0, (a, b) => a + b) / (bands.length - mid);

    final centre = Offset(size.width / 2, size.height / 2);
    // Wider than the album art it sits behind, or the knot — the whole point of
    // this one — would be hidden by the cover.
    final radius = math.min(size.width, size.height) * 0.72;

    canvas.saveLayer(Offset.zero & size, Paint());

    for (var ribbon = 0; ribbon < 3; ribbon++) {
      // Slowly drifting frequency ratio: the knot keeps re-tying itself.
      final a = 2 + ribbon + math.sin(p.time * 0.05 + ribbon) * 0.6;
      final b = 3 + ribbon * 0.5 + treble * 1.6;
      final phase = p.time * (0.6 + ribbon * 0.15);

      final path = Path();
      const steps = 130;
      for (var i = 0; i <= steps; i++) {
        final t = i / steps * 2 * math.pi;
        final r = radius * (0.55 + 0.45 * math.sin(t * 2 + phase * 0.5));
        final x = centre.dx + math.cos(a * t + phase) * r;
        final y = centre.dy + math.sin(b * t) * r * 0.78;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4 + energy * 2.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..blendMode = BlendMode.plus
          ..color = p.blend(ribbon / 2).withValues(alpha: 0.10 + energy * 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
      );
    }

    canvas.restore();
  }
}

/// Plenty: a flow field. Particles ride a slowly turning current and streak.
///
/// The particles are deterministic — position is a pure function of index and
/// time — so there is no state to keep and no allocation per frame; the sense of
/// continuity comes entirely from the trail.
class _PlentyPainter extends _VizPainter {
  const _PlentyPainter(super.p);

  @override
  void paint(Canvas canvas, Size size) {
    final bands = p.frame.bands;
    if (bands.isEmpty) return;

    final energy = bands.fold<double>(0, (a, b) => a + b) / bands.length;

    canvas.saveLayer(Offset.zero & size, Paint());

    const count = 90;
    for (var i = 0; i < count; i++) {
      final seed = i * 0.618; // golden-ratio spread, so they never clump
      final band = bands[i % bands.length];

      // Drift down the field, wrapping, with a curl that turns over time.
      final t = (p.time * (0.05 + band * 0.10) + seed) % 1.0;
      final baseX = ((seed * 7.13) % 1.0) * size.width;
      final curl = math.sin(t * 3 * math.pi + seed * 6 + p.time * 0.4);

      final x = baseX + curl * size.width * 0.16;
      final y = t * size.height;

      // Streak along the direction of travel — a dot leaves no wake.
      final len = 3 + band * 16 + energy * 8;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + curl * 3, y + len),
        Paint()
          ..strokeWidth = 1.0 + band * 2.2
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus
          ..color = p.blend((i % 7) / 6).withValues(alpha: 0.10 + band * 0.35),
      );
    }

    canvas.restore();
  }
}

/// Fire Storm: the spectrum as flame — tall, licking, hottest at the tips.
class _FireStormPainter extends _VizPainter {
  const _FireStormPainter(super.p);

  @override
  void paint(Canvas canvas, Size size) {
    final bands = p.frame.bands;
    if (bands.isEmpty) return;

    final slot = size.width / bands.length;

    for (var i = 0; i < bands.length; i++) {
      final level = bands[i].clamp(0.0, 1.0);
      // The flicker is what stops it reading as a bar chart.
      final flicker = 0.85 + 0.15 * math.sin(p.time * 9 + i * 1.9);
      final height = level * size.height * flicker;
      if (height < 2) continue;

      final x = i * slot + slot / 2;
      final base = size.height;
      final lean = math.sin(p.time * 2.2 + i * 0.6) * slot * 0.35;

      // A flame: wide at the base, drawn to a leaning point.
      final path = Path()
        ..moveTo(x - slot * 0.42, base)
        ..quadraticBezierTo(
          x - slot * 0.30,
          base - height * 0.55,
          x + lean,
          base - height,
        )
        ..quadraticBezierTo(
          x + slot * 0.30,
          base - height * 0.55,
          x + slot * 0.42,
          base,
        )
        ..close();

      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              p.primary.withValues(alpha: 0.9),
              p.blend(level).withValues(alpha: 0.85),
              p.secondary.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(
            Rect.fromLTWH(x - slot / 2, base - height, slot, height),
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
  }
}
