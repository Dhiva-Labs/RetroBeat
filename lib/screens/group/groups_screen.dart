import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/add_songs_sheet.dart';
import '../../core/widgets/empty_room.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/song_tile.dart';
import '../../data/models/song_model.dart';
import '../../providers/audio_provider.dart';
import '../../providers/group_provider.dart';

/// The Groups tab: user-defined buckets, plus a few that fill themselves.
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final groups = ref.watch(groupsProvider);
    final allSongs = ref.watch(songsProvider);

    return Column(
      children: [
        ListTile(
          onTap: () => _showCreateDialog(context, ref),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                Icon(Icons.create_new_folder_outlined, color: scheme.primary),
          ),
          title: Text(
            'New group',
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              final count =
                  songsInGroup(group.id, group.songIds, allSongs).length;

              return ListTile(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _GroupDetailScreen(groupId: group.id),
                  ),
                ),
                onLongPress: group.isSmartGroup
                    ? null
                    : () => _confirmDelete(context, ref, group.id, group.name),
                leading: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        _parseColor(group.colorHex, scheme.surfaceContainerHigh)
                            .withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      Text(group.emoji, style: const TextStyle(fontSize: 22)),
                ),
                title: Text(group.name),
                subtitle: Text('$count song${count == 1 ? '' : 's'}'),
                trailing: group.isSmartGroup
                    ? Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: scheme.outline,
                      )
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }

  static Color _parseColor(String hex, Color fallback) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return fallback;
    }
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String groupId,
    String name,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                'Delete "$name"',
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () {
                ref.read(groupsProvider.notifier).deleteGroup(groupId);
                Navigator.pop(sheetContext);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    var emoji = '🎵';
    var colorIndex = 0;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final scheme = Theme.of(dialogContext).colorScheme;

          return AlertDialog(
            title: const Text('New group'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Group name'),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Emoji',
                    style: Theme.of(dialogContext).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: AppConstants.groupEmojis.map((e) {
                      final selected = e == emoji;
                      return GestureDetector(
                        onTap: () => setState(() => emoji = e),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? scheme.primaryContainer
                                : scheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(e, style: const TextStyle(fontSize: 20)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Colour',
                    style: Theme.of(dialogContext).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children:
                        List.generate(AppColors.groupColors.length, (index) {
                      final selected = index == colorIndex;
                      return GestureDetector(
                        onTap: () => setState(() => colorIndex = index),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppColors.groupColors[index],
                            shape: BoxShape.circle,
                            border: selected
                                ? Border.all(color: scheme.onSurface, width: 2)
                                : null,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isEmpty) return;
                  final hex =
                      '#${AppColors.groupColors[colorIndex].toARGB32().toRadixString(16).substring(2)}';
                  ref.read(groupsProvider.notifier).createGroup(
                        name: name,
                        emoji: emoji,
                        colorHex: hex,
                      );
                  Navigator.pop(dialogContext);
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Smart groups compute their contents instead of storing song ids, so a new
/// download can appear in "Recently Added" without anyone adding it.
List<SongModel> songsInGroup(
  String groupId,
  List<int> songIds,
  List<SongModel> allSongs,
) {
  switch (groupId) {
    case 'group_favorites':
      return allSongs.where((s) => s.isFavorite).toList();
    case 'group_most_played':
      final played = allSongs.where((s) => s.playCount > 0).toList()
        ..sort((a, b) => b.playCount.compareTo(a.playCount));
      return played.take(50).toList();
    case 'group_recently_added':
      final recent = [...allSongs]..sort(
          (a, b) => (b.dateAdded ?? DateTime(1970))
              .compareTo(a.dateAdded ?? DateTime(1970)),
        );
      return recent.take(50).toList();
    default:
      return allSongs.where((s) => songIds.contains(s.id)).toList();
  }
}

class _GroupDetailScreen extends ConsumerWidget {
  const _GroupDetailScreen({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group =
        ref.watch(groupsProvider).where((g) => g.id == groupId).firstOrNull;

    if (group == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.error_outline_rounded,
          message: 'This group no longer exists.',
        ),
      );
    }

    final allSongs = ref.watch(songsProvider);
    final songs = songsInGroup(group.id, group.songIds, allSongs);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(group.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Flexible(child: Text(group.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          if (!group.isSmartGroup)
            IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: () =>
                  _addSongs(context, ref, group.name, allSongs, group.songIds),
            ),
        ],
      ),
      floatingActionButton: songs.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => playSongs(ref, songs, 0),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play'),
            ),
      body: songs.isEmpty
          ? EmptyState(
              illustration: const EmptyRoom(),
              message: group.isSmartGroup
                  ? 'Empty for now.\nThis group fills itself as you listen.'
                  : 'Empty for now.\nAdd a song to fill this space.',
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: songs.length,
              itemBuilder: (context, index) => SongTile(
                song: songs[index],
                onTap: () => playSongs(ref, songs, index),
              ),
            ),
    );
  }

  void _addSongs(
    BuildContext context,
    WidgetRef ref,
    String groupName,
    List<SongModel> allSongs,
    List<int> existingIds,
  ) {
    final available =
        allSongs.where((s) => !existingIds.contains(s.id)).toList();

    showAddSongsSheet(
      context,
      available: available,
      emptyMessage: 'Every song is already in this group.',
      containerName: groupName,
      onAdd: (song) =>
          ref.read(groupsProvider.notifier).addSongToGroup(groupId, song.id),
    );
  }
}
