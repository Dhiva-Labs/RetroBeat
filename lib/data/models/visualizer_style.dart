/// The visualisations, named after the Windows Media Player presets they are
/// modelled on.
///
/// Each one leans on a different part of the signal — the bar styles read the
/// spectrum, the scope styles read the waveform — which is why the analyser
/// captures both.
enum VisualizerStyle {
  // The flowing ones. These are what WMP 8 actually felt like: a continuous
  // field that never resets, more like a video than a chart. They rely on the
  // trail buffer — each frame is drawn over a faded copy of the last, which is
  // where the smearing, liquid quality comes from.
  ambience('Ambience', 'Flowing plasma that never repeats', flows: true),
  alchemy('Alchemy', 'Ribbons winding around each other', flows: true),
  plenty('Plenty', 'A drifting particle flow field', flows: true),

  // The Bars and Waves / Battery families.
  bars('Bars', 'The classic spectrum'),
  oceanMist('Ocean Mist', 'Mirrored bars with a drifting swell'),
  scope('Scope', 'An oscilloscope trace of the waveform'),
  battery('Battery', 'Spikes radiating from the centre'),
  fireStorm('Fire Storm', 'A burning spectrum');

  const VisualizerStyle(this.label, this.description, {this.flows = false});

  final String label;
  final String description;

  /// Whether this style is a full-bleed flowing field rather than a strip of
  /// bars. The player gives these the whole background.
  final bool flows;

  /// Wrap around, so tapping the visualiser cycles it the way WMP's
  /// next-visualisation arrow did.
  VisualizerStyle get next =>
      VisualizerStyle.values[(index + 1) % VisualizerStyle.values.length];
}
