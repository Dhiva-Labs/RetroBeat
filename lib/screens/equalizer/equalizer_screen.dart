import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/models/eq_preset_model.dart';
import '../../providers/equalizer_provider.dart';

/// Equalizer bound to the live playback pipeline.
///
/// Band count and centre frequencies are whatever the device reports, so the
/// slider row is built from [equalizerParametersProvider] rather than a fixed
/// list.
class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paramsAsync = ref.watch(equalizerParametersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer'),
        actions: [
          if (paramsAsync.valueOrNull != null) const _EqSwitch(),
          const SizedBox(width: 8),
        ],
      ),
      body: !ref.watch(equalizerServiceProvider).isSupported
          // just_audio's AudioPipeline has no equaliser outside Android
          // (DarwinAudioEffect is an empty mixin), so on iOS this is not a
          // "wait for playback" state — it is never coming.
          ? const _EqUnavailable(
              message: 'The equalizer is only available on Android.',
            )
          : paramsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const _EqUnavailable(
                message: 'The equalizer could not be started on this device.',
              ),
              data: (params) {
                if (params == null) {
                  return const _EqUnavailable(
                    message: 'Play a song to use the equalizer.\nYour device '
                        'reports its audio bands once playback starts.',
                  );
                }
                return _EqBody(params: params);
              },
            ),
    );
  }
}

class _EqSwitch extends ConsumerWidget {
  const _EqSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEnabled = ref.watch(eqEnabledProvider);
    return Switch(
      value: isEnabled,
      onChanged: (value) => ref.read(eqEnabledProvider.notifier).set(value),
    );
  }
}

class _EqUnavailable extends StatelessWidget {
  const _EqUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.equalizer_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EqBody extends ConsumerStatefulWidget {
  const _EqBody({required this.params});

  final AndroidEqualizerParameters params;

  @override
  ConsumerState<_EqBody> createState() => _EqBodyState();
}

class _EqBodyState extends ConsumerState<_EqBody> {
  @override
  void initState() {
    super.initState();
    // Size the gain list to this device's bands and restore saved values.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bandGainsProvider.notifier).hydrate(widget.params.bands.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = ref.watch(eqEnabledProvider);
    final gains = ref.watch(bandGainsProvider);
    final presets = ref.watch(eqPresetsProvider);
    final activePresetId = ref.watch(activePresetIdProvider);

    if (gains.length != widget.params.bands.length) {
      return const Center(child: CircularProgressIndicator());
    }

    return AnimatedOpacity(
      opacity: isEnabled ? 1.0 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: AbsorbPointer(
        absorbing: !isEnabled,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _EqCurve(gains: gains, params: widget.params),
            const SizedBox(height: 24),
            _BandSliders(
              params: widget.params,
              gains: gains,
              onChanged: _onBandChanged,
            ),
            const SizedBox(height: 32),
            Text(
              'Presets',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 12),
            _PresetChips(
              presets: presets,
              activePresetId: activePresetId,
              onSelected: _onPresetSelected,
              onDeleted: _onPresetDeleted,
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _onReset,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reset'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _showSavePresetDialog,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Save as preset'),
                ),
              ],
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  void _onBandChanged(int index, double gain) {
    ref.read(bandGainsProvider.notifier).setBand(index, gain);
    // Hand-tuning a band means the sound no longer matches the chosen preset.
    if (ref.read(activePresetIdProvider) != null) {
      ref.read(activePresetIdProvider.notifier).state = null;
      ref.read(equalizerRepositoryProvider).clearActivePreset();
    }
  }

  void _onPresetSelected(EqPresetModel preset) {
    ref.read(bandGainsProvider.notifier).applyPreset(preset);
    ref.read(activePresetIdProvider.notifier).state = preset.id;
  }

  void _onReset() {
    ref.read(bandGainsProvider.notifier).reset();
    ref.read(activePresetIdProvider.notifier).state = null;
  }

  Future<void> _onPresetDeleted(EqPresetModel preset) async {
    final repo = ref.read(equalizerRepositoryProvider);
    await repo.deletePreset(preset.id);
    if (!mounted) return;

    ref.read(eqPresetsProvider.notifier).state = repo.getAllPresets();
    // Deleting the preset that is currently applied leaves the gains alone —
    // the sound does not change, it just stops having a name.
    if (ref.read(activePresetIdProvider) == preset.id) {
      ref.read(activePresetIdProvider.notifier).state = null;
      await repo.clearActivePreset();
    }
  }

  Future<void> _showSavePresetDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save as preset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Preset name'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty || !mounted) return;

    final repo = ref.read(equalizerRepositoryProvider);
    final preset = await repo.createCustomPreset(
      name: name,
      bandLevels: ref.read(bandGainsProvider.notifier).asPresetCurve(),
    );
    if (!mounted) return;

    ref.read(eqPresetsProvider.notifier).state = repo.getAllPresets();
    ref.read(activePresetIdProvider.notifier).state = preset.id;
    await repo.setActivePreset(preset.id);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved "$name"')),
    );
  }
}

class _BandSliders extends StatelessWidget {
  const _BandSliders({
    required this.params,
    required this.gains,
    required this.onChanged,
  });

  final AndroidEqualizerParameters params;
  final List<double> gains;
  final void Function(int index, double gain) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(params.bands.length, (index) {
        final band = params.bands[index];
        return Expanded(
          child: Column(
            children: [
              Text(
                '${gains[index].toStringAsFixed(0)} dB',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 200,
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Slider(
                    value: gains[index]
                        .clamp(params.minDecibels, params.maxDecibels),
                    min: params.minDecibels,
                    max: params.maxDecibels,
                    onChanged: (value) => onChanged(index, value),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatHz(band.centerFrequency),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        );
      }),
    );
  }

  static String _formatHz(double hz) {
    if (hz >= 1000) {
      final k = hz / 1000;
      final text = k >= 10 ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
      return '${text.replaceAll(RegExp(r'\.0$'), '')}k';
    }
    return hz.toStringAsFixed(0);
  }
}

class _PresetChips extends StatelessWidget {
  const _PresetChips({
    required this.presets,
    required this.activePresetId,
    required this.onSelected,
    required this.onDeleted,
  });

  final List<EqPresetModel> presets;
  final String? activePresetId;
  final void Function(EqPresetModel preset) onSelected;
  final void Function(EqPresetModel preset) onDeleted;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: presets.map((preset) {
        final isActive = preset.id == activePresetId;
        return FilterChip(
          label: Text(preset.name),
          selected: isActive,
          onSelected: (selected) {
            if (selected) onSelected(preset);
          },
          // Only the user's own presets can be removed; the built-ins stay.
          onDeleted: preset.isCustom ? () => onDeleted(preset) : null,
        );
      }).toList(),
    );
  }
}

/// Draws the current gain curve across the device's bands.
class _EqCurve extends StatelessWidget {
  const _EqCurve({required this.gains, required this.params});

  final List<double> gains;
  final AndroidEqualizerParameters params;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      // A spline through the band points can overshoot vertically between
      // control points, so keep it inside the card.
      child: ClipRect(
        child: CustomPaint(
          size: const Size(double.infinity, 88),
          painter: _EqCurvePainter(
            gains: gains,
            minDecibels: params.minDecibels,
            maxDecibels: params.maxDecibels,
            lineColor: Theme.of(context).colorScheme.primary,
            gridColor: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}

class _EqCurvePainter extends CustomPainter {
  _EqCurvePainter({
    required this.gains,
    required this.minDecibels,
    required this.maxDecibels,
    required this.lineColor,
    required this.gridColor,
  });

  final List<double> gains;
  final double minDecibels;
  final double maxDecibels;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (gains.isEmpty) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      gridPaint,
    );

    final range = maxDecibels - minDecibels;
    final points = <Offset>[];
    for (var i = 0; i < gains.length; i++) {
      final x = gains.length == 1
          ? size.width / 2
          : size.width * i / (gains.length - 1);
      // Normalise the gain into 0..1 across the device's supported range.
      final normalised =
          range == 0 ? 0.5 : ((gains[i] - minDecibels) / range).clamp(0.0, 1.0);
      final y = size.height - (normalised * size.height);
      points.add(Offset(x, y));
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final midX = (points[i - 1].dx + points[i].dx) / 2;
      path.cubicTo(
        midX,
        points[i - 1].dy,
        midX,
        points[i].dy,
        points[i].dx,
        points[i].dy,
      );
    }
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = lineColor;
    for (final point in points) {
      canvas.drawCircle(point, 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _EqCurvePainter oldDelegate) {
    return oldDelegate.gains != gains ||
        oldDelegate.minDecibels != minDecibels ||
        oldDelegate.maxDecibels != maxDecibels ||
        oldDelegate.lineColor != lineColor;
  }
}
