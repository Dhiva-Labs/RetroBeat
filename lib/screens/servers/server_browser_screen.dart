import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/empty_state.dart';
import '../../data/repositories/media_repository.dart';
import '../../providers/audio_provider.dart';
import '../../providers/server_providers.dart';
import '../home/widgets/mini_player.dart';
import 'destination_picker_sheet.dart';
import 'providers/directory_listing_provider.dart';
import 'transfers_screen.dart';
import 'widgets/breadcrumbs.dart';
import 'widgets/entry_format.dart';
import 'widgets/server_switcher_chips.dart';

enum _FileAction { copy, move }

/// Folders and files on the active server, from its configured root down.
/// Tapping an audio file plays the whole folder starting there; any file also
/// offers Copy/Move to another connected server (or another folder on this
/// one).
class ServerBrowserScreen extends ConsumerStatefulWidget {
  const ServerBrowserScreen({super.key});

  @override
  ConsumerState<ServerBrowserScreen> createState() =>
      _ServerBrowserScreenState();
}

class _ServerBrowserScreenState extends ConsumerState<ServerBrowserScreen> {
  String? _forServerId;
  String _path = '/';

  /// Resets the browse path when the active server changes — including the
  /// first build — so switching servers starts back at that server's root
  /// rather than reusing whatever path the last one was showing.
  void _syncPathFor(ServerConfigModel config) {
    if (_forServerId != config.id) {
      _forServerId = config.id;
      _path = config.rootPath;
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(activeServerConfigProvider);
    if (config == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Browse')),
        body: const EmptyState(
          icon: Icons.dns_rounded,
          message: 'No server selected.',
        ),
      );
    }
    _syncPathFor(config);

    final sessions = ref.watch(connectedSessionsProvider);
    final key = (serverId: config.id, path: _path);
    final listing = ref.watch(directoryListingProvider(key));

    return Scaffold(
      appBar: AppBar(
        title: Text(config.name),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(directoryListingProvider(key)),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              ServerSwitcherChips(
                sessions: sessions,
                activeServerId: config.id,
                onSelect: (id) =>
                    ref.read(activeServerProvider.notifier).state = id,
              ),
              ServerBreadcrumbs(
                rootPath: config.rootPath,
                currentPath: _path,
                onSelect: (path) => setState(() => _path = path),
              ),
              const Divider(height: 1),
              Expanded(
                child: listing.when(
                  data: (entries) => entries.isEmpty
                      ? const Center(
                          child: EmptyState(
                            icon: Icons.folder_off_outlined,
                            message: 'This folder is empty.',
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () =>
                              ref.refresh(directoryListingProvider(key).future),
                          child: _DirectoryList(
                            entries: entries,
                            config: config,
                            folderPath: _path,
                            onOpenFolder: (path) =>
                                setState(() => _path = path),
                          ),
                        ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: EmptyState(
                      icon: Icons.cloud_off_rounded,
                      message: describeDirectoryError(error),
                      action: FilledButton.icon(
                        onPressed: () =>
                            ref.invalidate(directoryListingProvider(key)),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
        ],
      ),
    );
  }
}

class _DirectoryList extends ConsumerWidget {
  const _DirectoryList({
    required this.entries,
    required this.config,
    required this.folderPath,
    required this.onOpenFolder,
  });

  final List<WebDavEntry> entries;
  final ServerConfigModel config;
  final String folderPath;
  final ValueChanged<String> onOpenFolder;

  bool _isAudioFile(WebDavEntry entry) {
    if (entry.isDir) return false;
    final ext = entry.extension;
    return ext.isNotEmpty &&
        MediaRepository.desktopExtensions.contains('.$ext');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final audioEntries = entries.where(_isAudioFile).toList();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];

        if (entry.isDir) {
          return ListTile(
            key: ValueKey('entry_${entry.path}'),
            leading: Icon(Icons.folder_rounded, color: scheme.onSurfaceVariant),
            title:
                Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => onOpenFolder(entry.path),
          );
        }

        final isAudio = _isAudioFile(entry);
        final dateLabel = entry.lastModified == null
            ? ''
            : formatEntryDate(entry.lastModified!);
        return ListTile(
          key: ValueKey('entry_${entry.path}'),
          leading: Icon(
            isAudio
                ? Icons.music_note_rounded
                : Icons.insert_drive_file_outlined,
            color: scheme.onSurfaceVariant,
          ),
          title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            dateLabel.isEmpty
                ? formatBytes(entry.size)
                : '${formatBytes(entry.size)} · $dateLabel',
          ),
          onTap: isAudio ? () => _play(ref, audioEntries, entry) : null,
          onLongPress: () => _showFileMenu(context, ref, entry),
          trailing: IconButton(
            key: ValueKey('fileMenu_${entry.path}'),
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () => _showFileMenu(context, ref, entry),
          ),
        );
      },
    );
  }

  Future<void> _play(
    WidgetRef ref,
    List<WebDavEntry> audioEntries,
    WebDavEntry tapped,
  ) async {
    final index = audioEntries.indexWhere((e) => e.path == tapped.path);
    if (index < 0) return;
    await playRemoteQueue(
      ref,
      serverId: config.id,
      serverName: config.name,
      folderName:
          folderPath == '/' ? 'Root' : WebDavClient.basename(folderPath),
      entries: audioEntries,
      index: index,
    );
  }

  Future<void> _showFileMenu(
    BuildContext context,
    WidgetRef ref,
    WebDavEntry entry,
  ) async {
    final action = await showModalBottomSheet<_FileAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_copy_outlined),
              title: const Text('Copy to…'),
              onTap: () => Navigator.pop(sheetContext, _FileAction.copy),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Move to…'),
              onTap: () => Navigator.pop(sheetContext, _FileAction.move),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    final destination = await showDestinationPicker(
      context,
      initialServerId: config.id,
      initialPath: folderPath,
    );
    if (destination == null || !context.mounted) return;

    ref.read(transferEngineProvider.notifier).enqueue(
          srcServerId: config.id,
          srcPath: entry.path,
          dstServerId: destination.serverId,
          dstDir: destination.path,
          mode: action == _FileAction.copy
              ? TransferMode.copy
              : TransferMode.move,
          totalBytes: entry.size,
        );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${action == _FileAction.copy ? 'Copying' : 'Moving'} '
          '${entry.name}…',
        ),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TransfersScreen()),
          ),
        ),
      ),
    );
  }
}
