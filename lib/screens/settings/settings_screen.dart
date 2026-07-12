import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/visualizer_style.dart';
import '../../providers/audio_provider.dart';
import '../../providers/folders_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/tabs_provider.dart';
import '../../providers/visualizer_provider.dart';
import '../equalizer/equalizer_screen.dart';
import 'folders_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeProvider);
    final isRetro = ref.watch(retroModeProvider);
    final minDurationFilter = ref.watch(minDurationFilterProvider);
    final autoRescan = ref.watch(autoRescanProvider);
    final excludedCount = ref.watch(excludedFoldersProvider).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Library'),
          ListTile(
            leading: const Icon(Icons.refresh_rounded),
            title: const Text('Rescan library'),
            subtitle: const Text('Look for music added since last time'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              await ref.read(libraryLoaderProvider).load(prompt: false);
              final count = ref.read(songsProvider).length;
              messenger.showSnackBar(
                SnackBar(content: Text('Found $count songs')),
              );
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.sync_rounded),
            title: const Text('Auto rescan'),
            subtitle: const Text(
              'Look for new music automatically when you open the app',
            ),
            value: autoRescan,
            onChanged: (_) => ref.read(autoRescanProvider.notifier).toggle(),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.filter_list_rounded),
            title: const Text('Hide short audio'),
            subtitle: const Text('Skip clips under 30 seconds'),
            value: minDurationFilter,
            onChanged: (_) async {
              ref.read(minDurationFilterProvider.notifier).toggle();
              // Rescan, or the change would not reach the library until the
              // next launch and the toggle would look broken.
              await ref.read(libraryLoaderProvider).load(prompt: false);
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_off_outlined),
            title: const Text('Folders'),
            subtitle: Text(
              excludedCount == 0
                  ? 'All folders included'
                  : '$excludedCount folder${excludedCount == 1 ? '' : 's'} excluded',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FoldersScreen()),
            ),
          ),
          const _SectionHeader('Audio'),
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('Equalizer'),
            subtitle: const Text('Presets, or tune each band yourself'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EqualizerScreen()),
            ),
          ),
          const _SectionHeader('Tabs'),
          const _TabsSetting(),
          const _SectionHeader('Appearance'),
          SwitchListTile(
            secondary: Icon(
              isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
            ),
            title: const Text('Dark mode'),
            // Retro brings its own palette, so there is nothing to switch.
            subtitle: isRetro
                ? const Text('Turn off Retro mode to choose light or dark')
                : null,
            value: isDarkMode,
            onChanged: isRetro
                ? null
                : (_) => ref.read(themeProvider.notifier).toggleTheme(),
          ),
          const _RetroSetting(),
          const _SectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('Version'),
            subtitle: const Text(AppConstants.appVersion),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Retro mode, and the visualiser that comes with it.
///
/// The second switch is the interesting one. By default the bars are an
/// animation — they move while music plays but they are not reading it. Saying
/// so plainly is the whole point: the alternative is a meter that looks like it
/// is tracking your audio when it never sees it.
class _RetroSetting extends ConsumerWidget {
  const _RetroSetting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isRetro = ref.watch(retroModeProvider);
    final isReactive = ref.watch(audioReactiveVisualizerProvider);

    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.graphic_eq_rounded),
          title: const Text('Retro mode'),
          subtitle: const Text(
            'Windows Media Player skin, with a visualiser on the player',
          ),
          value: isRetro,
          onChanged: (value) => ref.read(retroModeProvider.notifier).set(value),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState:
              isRetro ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Column(
            children: [
              const _VisualizerStylePicker(),
              // The real analyser is a native Android channel. Offering the
              // switch on a platform where it cannot work would just be another
              // control that does nothing.
              if (ref.watch(visualizerServiceProvider).isSupported)
                SwitchListTile(
                  secondary: const Icon(Icons.multitrack_audio_rounded),
                  title: const Text('Audio-reactive'),
                  subtitle: Text(
                    isReactive
                        ? 'The visualisation follows the real sound'
                        : 'Off: the visualisation is an animation, not the '
                            'actual audio. Turning this on needs the microphone '
                            'permission — Android requires it to read the '
                            'waveform, even of our own playback. Nothing is '
                            'recorded.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  isThreeLine: !isReactive,
                  value: isReactive,
                  onChanged: (value) => _setReactive(context, ref, value),
                ),
            ],
          ),
          secondChild: const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Future<void> _setReactive(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    final notifier = ref.read(audioReactiveVisualizerProvider.notifier);

    if (!value) {
      await notifier.set(false);
      return;
    }

    // Only ask at the moment it is switched on, so the prompt always has an
    // obvious cause.
    final granted =
        await ref.read(visualizerServiceProvider).requestPermission();
    if (!context.mounted) return;

    if (!granted) {
      // Leave the switch off rather than showing it on with dead bars.
      await notifier.set(false);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Without the microphone permission the bars stay decorative.',
          ),
        ),
      );
      return;
    }

    await notifier.set(true);
  }
}

/// Pick the visualisation. Also reachable by tapping the visualiser itself,
/// which is how WMP let you flick through them.
class _VisualizerStylePicker extends ConsumerWidget {
  const _VisualizerStylePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final selected = ref.watch(visualizerStyleProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            'Visualisation',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
          child: Text(
            '${selected.description}. Tap the visualiser to flick through them.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: VisualizerStyle.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final style = VisualizerStyle.values[index];
              return ChoiceChip(
                label: Text(style.label),
                selected: style == selected,
                onSelected: (_) =>
                    ref.read(visualizerStyleProvider.notifier).set(style),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Choose which library views appear in the tab bar, and in what order.
class _TabsSetting extends ConsumerWidget {
  const _TabsSetting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final visible = ref.watch(visibleTabsProvider);
    final notifier = ref.read(visibleTabsProvider.notifier);

    // Visible tabs first, in their bar order, so the list mirrors what the user
    // sees; hidden ones follow.
    final hidden =
        LibraryTab.values.where((t) => !visible.contains(t)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Drag to reorder. Tracks and Playlists always stay.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: notifier.reorder,
          children: [
            for (var i = 0; i < visible.length; i++)
              ListTile(
                key: ValueKey(visible[i]),
                leading: Icon(visible[i].icon, color: scheme.onSurfaceVariant),
                title: Text(visible[i].label),
                subtitle:
                    visible[i].isPermanent ? const Text('Always shown') : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: true,
                      onChanged: visible[i].isPermanent
                          ? null
                          : (_) => notifier.setVisible(visible[i], false),
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.drag_handle_rounded,
                          color: scheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        for (final tab in hidden)
          ListTile(
            leading: Icon(tab.icon, color: scheme.outline),
            title: Text(
              tab.label,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            trailing: Switch(
              value: false,
              onChanged: (_) => notifier.setVisible(tab, true),
            ),
          ),
      ],
    );
  }
}
