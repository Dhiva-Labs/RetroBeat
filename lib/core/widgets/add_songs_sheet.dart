import 'package:flutter/material.dart';

import '../../data/models/song_model.dart';
import 'artwork.dart';
import 'empty_state.dart';

/// The song picker shared by "Add to Playlist" and "Add to Group": a search
/// field over the library, not a plain scrollable list — scrolling to find one
/// song in a few thousand was never a realistic way to build a playlist.
///
/// The sheet stays open after each tap so several songs can be added in one
/// pass; each tap confirms with a snackbar naming what was added and where,
/// since silently doing nothing visible left people tapping twice wondering
/// if it had worked.
Future<void> showAddSongsSheet(
  BuildContext context, {
  required List<SongModel> available,
  required String emptyMessage,
  required String containerName,
  required void Function(SongModel song) onAdd,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _AddSongsSheet(
      available: available,
      emptyMessage: emptyMessage,
      containerName: containerName,
      onAdd: onAdd,
    ),
  );
}

class _AddSongsSheet extends StatefulWidget {
  const _AddSongsSheet({
    required this.available,
    required this.emptyMessage,
    required this.containerName,
    required this.onAdd,
  });

  final List<SongModel> available;
  final String emptyMessage;
  final String containerName;
  final void Function(SongModel song) onAdd;

  @override
  State<_AddSongsSheet> createState() => _AddSongsSheetState();
}

class _AddSongsSheetState extends State<_AddSongsSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<SongModel> get _results {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.available;
    return widget.available.where((song) {
      return song.title.toLowerCase().contains(query) ||
          song.artist.toLowerCase().contains(query) ||
          song.album.toLowerCase().contains(query);
    }).toList();
  }

  void _add(SongModel song) {
    widget.onAdd(song);
    // hideCurrentSnackBar first, or adding several songs quickly queues up a
    // pile of snackbars that keep the last one on screen for ages.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Added "${song.title}" to ${widget.containerName}'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              'Add songs',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (widget.available.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                controller: _controller,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search songs, artists, albums',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
          Expanded(
            child: widget.available.isEmpty
                ? EmptyState(
                    icon: Icons.check_rounded,
                    message: widget.emptyMessage,
                  )
                : results.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off_rounded,
                        message: 'No songs match "$_query"',
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final song = results[index];
                          return ListTile(
                            leading: Artwork(id: song.id),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.add_rounded),
                            onTap: () => _add(song),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
