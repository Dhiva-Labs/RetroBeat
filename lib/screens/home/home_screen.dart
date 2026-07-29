import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/platform_info.dart';
import '../../providers/audio_provider.dart';
import '../../providers/tabs_provider.dart';
import '../group/groups_screen.dart';
import '../library/browse_tabs.dart';
import '../library/songs_tab.dart';
import '../playlist/playlists_screen.dart';
import '../servers/widgets/servers_entry_button.dart';
import '../settings/settings_screen.dart';
import 'widgets/mini_player.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _closeSearch() {
    setState(() => _isSearching = false);
    _searchController.clear();
    ref.read(searchQueryProvider.notifier).state = '';
  }

  Widget _viewFor(LibraryTab tab) {
    return switch (tab) {
      LibraryTab.tracks => const SongsTab(),
      LibraryTab.albums => const AlbumsTab(),
      LibraryTab.artists => const ArtistsTab(),
      LibraryTab.playlists => const PlaylistsScreen(),
      LibraryTab.liked => const LikedTab(),
      LibraryTab.genres => const GenresTab(),
      LibraryTab.groups => const GroupsScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(visibleTabsProvider);

    // Keyed so that changing the visible tabs in Settings rebuilds the
    // controller instead of leaving it pointing at a tab that no longer exists.
    return DefaultTabController(
      key: ValueKey(tabs.join()),
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          leading: _isSearching
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _closeSearch,
                )
              : null,
          title: _isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search songs, artists, albums',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (value) =>
                      ref.read(searchQueryProvider.notifier).state = value,
                )
              : const Text('Music'),
          actions: [
            if (_isSearching)
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _closeSearch,
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.search_rounded),
                onPressed: () => setState(() => _isSearching = true),
              ),
              if (PlatformInfo.isDesktop) const ServersEntryButton(),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
            const SizedBox(width: 4),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.only(left: 12),
            tabs: [for (final tab in tabs) Tab(text: tab.label)],
          ),
        ),
        body: Stack(
          children: [
            TabBarView(
              children: [for (final tab in tabs) _viewFor(tab)],
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MiniPlayer(),
            ),
          ],
        ),
      ),
    );
  }
}
