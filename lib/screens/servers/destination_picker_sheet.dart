import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/empty_state.dart';
import '../../providers/server_providers.dart';
import 'providers/directory_listing_provider.dart';
import 'widgets/breadcrumbs.dart';
import 'widgets/server_switcher_chips.dart';

/// Where a copy or move should land: a server and a folder inside it.
class DestinationChoice {
  const DestinationChoice({required this.serverId, required this.path});

  final String serverId;
  final String path;
}

/// Opens the destination picker and resolves to the chosen folder, or null if
/// the user backed out.
Future<DestinationChoice?> showDestinationPicker(
  BuildContext context, {
  required String initialServerId,
  required String initialPath,
}) {
  return showModalBottomSheet<DestinationChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DestinationPickerSheet(
      initialServerId: initialServerId,
      initialPath: initialPath,
    ),
  );
}

/// Picks a folder on any connected server — including the source, since a
/// same-server move is legal and cheap (the engine uses WebDAV's own MOVE).
class DestinationPickerSheet extends ConsumerStatefulWidget {
  const DestinationPickerSheet({
    super.key,
    required this.initialServerId,
    required this.initialPath,
  });

  final String initialServerId;
  final String initialPath;

  @override
  ConsumerState<DestinationPickerSheet> createState() =>
      _DestinationPickerSheetState();
}

class _DestinationPickerSheetState
    extends ConsumerState<DestinationPickerSheet> {
  late String _serverId = widget.initialServerId;
  late String _path = widget.initialPath;

  void _switchTo(ServerConfigModel config) {
    setState(() {
      _serverId = config.id;
      _path = config.rootPath;
    });
  }

  Future<void> _newFolder(WebDavClient client) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    try {
      await client.mkcol(WebDavClient.joinPath(_path, name));
      final key = (serverId: _serverId, path: _path);
      ref.invalidate(directoryListingProvider(key));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeServerError(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(connectedSessionsProvider);
    final configs = ref.watch(serverListProvider);
    final config = configs.where((c) => c.id == _serverId).firstOrNull;
    final client =
        ref.read(serverSessionsProvider.notifier).clientFor(_serverId);
    final key = (serverId: _serverId, path: _path);

    return DraggableScrollableSheet(
      key: const Key('destinationPicker'),
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose a destination',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            ServerSwitcherChips(
              sessions: sessions,
              activeServerId: _serverId,
              onSelect: (id) {
                final target = configs.where((c) => c.id == id).firstOrNull;
                if (target != null) _switchTo(target);
              },
            ),
            if (config != null)
              ServerBreadcrumbs(
                rootPath: config.rootPath,
                currentPath: _path,
                onSelect: (path) => setState(() => _path = path),
              ),
            const Divider(height: 1),
            Expanded(
              child: client == null
                  ? const Center(
                      child: EmptyState(
                        icon: Icons.cloud_off_rounded,
                        message: 'This server is not connected.',
                      ),
                    )
                  : Consumer(
                      builder: (context, ref, _) {
                        final listing =
                            ref.watch(directoryListingProvider(key));
                        return listing.when(
                          data: (entries) => ListView.builder(
                            controller: scrollController,
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return ListTile(
                                enabled: entry.isDir,
                                leading: Icon(
                                  entry.isDir
                                      ? Icons.folder_rounded
                                      : Icons.insert_drive_file_outlined,
                                ),
                                title: Text(
                                  entry.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: entry.isDir
                                    ? () => setState(() => _path = entry.path)
                                    : null,
                              );
                            },
                          ),
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, _) => Center(
                            child: EmptyState(
                              icon: Icons.cloud_off_rounded,
                              message: describeDirectoryError(error),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('destinationPicker_newFolder'),
                    tooltip: 'New folder',
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: client == null ? null : () => _newFolder(client),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const Key('destinationPicker_choose'),
                    onPressed: client == null
                        ? null
                        : () => Navigator.pop(
                              context,
                              DestinationChoice(
                                serverId: _serverId,
                                path: _path,
                              ),
                            ),
                    child: const Text('Choose this folder'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
