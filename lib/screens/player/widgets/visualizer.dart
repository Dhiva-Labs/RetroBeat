import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/visualizer_style.dart';
import '../../../data/services/visualizer_service.dart';
import '../../../providers/audio_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/visualizer_provider.dart';
import 'visualizer_painters.dart';

/// The Windows Media Player visualisations.
///
/// Two sources, and the difference matters:
///
/// * **Audio-reactive** (opt-in): the real spectrum and waveform of the playing
///   audio.
/// * **Animation** (default): a procedural signal. It is *not* reading the
///   sound. It is decoration that moves while music plays, and the Settings
///   screen says so — a meter that pretends to track audio it never sees is a
///   lie, and this app has had enough of those.
///
/// The flowing styles keep a **trail buffer**: each frame is drawn on top of a
/// faded, slightly zoomed copy of the previous one. That feedback is the whole
/// reason WMP's flows looked like video rather than a redrawn chart — no single
/// frame contains the image you actually see, only its newest layer.
///
/// Tap to cycle to the next visualisation, as WMP's little arrow did.
class Visualizer extends ConsumerStatefulWidget {
  const Visualizer({
    super.key,
    this.height = 96,
    this.expand = false,
  });

  /// Fixed height for the strip styles. Ignored when [expand] is set.
  final double height;

  /// Fill the parent instead — used when a flowing style takes the whole player
  /// background.
  final bool expand;

  @override
  ConsumerState<Visualizer> createState() => _VisualizerState();
}

class _VisualizerState extends ConsumerState<Visualizer>
    with SingleTickerProviderStateMixin {
  /// Started in initState, not as a `late` initialiser: a `late` field is lazy,
  /// and nothing here ever reads the ticker, so it would never be created and
  /// the visualiser would sit perfectly still.
  Ticker? _ticker;

  /// The accumulated image. This *is* the visualisation for flowing styles.
  ui.Image? _trail;

  Duration _elapsed = Duration.zero;
  Duration _renderedAt = Duration.zero;
  Size _size = Size.zero;
  VisualizerStyle? _lastStyle;

  /// The buffer is rendered below screen resolution: it is cheaper, and the
  /// softness on upscale is exactly the look these visualisations had.
  static const double _bufferScale = 0.55;

  /// Bars fall slower than they rise, the way a level meter does — it is what
  /// makes the movement read as sound rather than as a wobble.
  final List<double> _levels =
      List.filled(VisualizerFrame.bandCount, 0, growable: false);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _trail?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    if (mounted) setState(() {});
  }

  List<double> _smooth(List<double> target) {
    for (var i = 0; i < _levels.length; i++) {
      final next = i < target.length ? target[i] : 0.0;
      _levels[i] = next > _levels[i]
          ? next // attack: jump straight up
          : _levels[i] * 0.80 + next * 0.20; // release: ease down
    }
    return List<double>.from(_levels);
  }

  /// A standing wave that never claims to be the audio.
  VisualizerFrame _procedural(double t, bool isPlaying) {
    if (!isPlaying) return VisualizerFrame.silent;

    final bands = List<double>.generate(VisualizerFrame.bandCount, (i) {
      final x = i / VisualizerFrame.bandCount;
      final a = math.sin((x * 5.5) + t * 2.0 * math.pi);
      final b = math.sin((x * 13.0) - t * 3.1 * math.pi);
      final c = math.sin((x * 2.0) + t * 1.3 * math.pi);
      // Bass end sits higher, as it does in real music.
      final envelope = 1.0 - (x * 0.55);
      return (((a + b * 0.5 + c * 0.8) / 2.3 + 1) / 2 * envelope)
          .clamp(0.05, 1.0);
    });

    final wave = List<double>.generate(VisualizerFrame.wavePoints, (i) {
      final x = i / VisualizerFrame.wavePoints;
      return (math.sin(x * 8 * math.pi + t * 6 * math.pi) * 0.55 +
              math.sin(x * 21 * math.pi - t * 4 * math.pi) * 0.25)
          .clamp(-1.0, 1.0);
    });

    return VisualizerFrame(bands: bands, wave: wave);
  }

  /// Composite this frame over the faded previous one and keep the result.
  ///
  /// Guarded on the tick so a rebuild from anything other than the clock (a
  /// theme change, a provider update) does not advance the trail twice.
  void _renderTrail(VisualizerStyle style, VisualizerPaint paint, Size size) {
    if (_elapsed == _renderedAt && _trail != null) return;
    _renderedAt = _elapsed;

    final width = (size.width * _bufferScale).round();
    final height = (size.height * _bufferScale).round();
    if (width <= 0 || height <= 0) return;

    final bufferSize = Size(width.toDouble(), height.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final previous = _trail;
    final persistence = trailPersistenceFor(style);

    if (previous != null && persistence > 0) {
      // A hair of zoom each frame is what pulls the trail outward and gives the
      // flow its sense of depth, instead of a static ghost.
      canvas.save();
      canvas.translate(bufferSize.width / 2, bufferSize.height / 2);
      canvas.scale(1.008);
      canvas.translate(-bufferSize.width / 2, -bufferSize.height / 2);
      canvas.drawImageRect(
        previous,
        Offset.zero & bufferSize,
        Offset.zero & bufferSize,
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, persistence)
          ..filterQuality = FilterQuality.low,
      );
      canvas.restore();
    }

    painterFor(style, paint).paint(canvas, bufferSize);

    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();

    previous?.dispose();
    _trail = image;
  }

  void _clearTrail() {
    _trail?.dispose();
    _trail = null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = ref.watch(visualizerStyleProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final live = ref.watch(visualizerFrameProvider).valueOrNull;

    // Switching style must not smear the old one into the new.
    if (style != _lastStyle) {
      _clearTrail();
      _lastStyle = style;
    }

    final seconds = _elapsed.inMicroseconds / 1e6;
    final source = live ?? _procedural(seconds / 10, isPlaying);

    final paint = VisualizerPaint(
      frame: VisualizerFrame(
        bands: _smooth(source.bands),
        wave: source.wave,
      ),
      primary: scheme.primary,
      secondary: scheme.secondary,
      time: seconds,
    );

    final child = LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _size) {
          _size = size;
          _clearTrail();
        }

        if (!style.flows) {
          // No trail: a meter that never falls is not a meter.
          return CustomPaint(
            size: Size.infinite,
            painter: painterFor(style, paint),
          );
        }

        _renderTrail(style, paint, size);
        final trail = _trail;
        if (trail == null) return const SizedBox.expand();

        return RawImage(
          // RawImage takes ownership and disposes the image when it is replaced,
          // so it gets a clone: the buffer we keep for the next frame's
          // feedback pass has to outlive this widget's copy.
          image: trail.clone(),
          width: size.width,
          height: size.height,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.medium,
        );
      },
    );

    return GestureDetector(
      onTap: () => ref.read(visualizerStyleProvider.notifier).cycle(),
      behavior: HitTestBehavior.opaque,
      child: ClipRect(
        child: widget.expand
            ? SizedBox.expand(child: child)
            : SizedBox(height: widget.height, child: child),
      ),
    );
  }
}
