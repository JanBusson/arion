import 'package:flutter/material.dart';

import '../library/catalog_api.dart';
import '../library/library_controller.dart';
import '../library/track.dart';
import '../playback/playback_controller.dart';
import 'now_playing_panel.dart';

final class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    required this.library,
    required this.playback,
    required this.api,
    required this.onOpenSettings,
    super.key,
  });

  final LibraryController library;
  final PlaybackController playback;
  final CatalogApi api;
  final VoidCallback onOpenSettings;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

final class _LibraryScreenState extends State<LibraryScreen> {
  late final TextEditingController _search;
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.library.query);
    _scroll = ScrollController()..addListener(_loadMoreNearEnd);
    widget.library.loadInitial();
  }

  void _loadMoreNearEnd() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 320 &&
        widget.library.hasMore) {
      widget.library.loadMore();
    }
  }

  Future<void> _clearSearch() async {
    _search.clear();
    await widget.library.clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arion'),
        actions: [
          IconButton(
            tooltip: 'Server settings',
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: TextField(
                  key: const Key('library-search-field'),
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search title, artist, or album',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Clear search',
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.clear),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: widget.library.submitSearch,
                ),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.library,
                builder: (context, _) => _LibraryBody(
                  controller: widget.library,
                  scrollController: _scroll,
                  coverUri: widget.api.coverUri,
                  onPlay: (track) => widget.playback.selectAndPlay(
                    track,
                    widget.api.audioUri(track.id),
                  ),
                ),
              ),
            ),
            NowPlayingPanel(controller: widget.playback),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

final class _LibraryBody extends StatelessWidget {
  const _LibraryBody({
    required this.controller,
    required this.scrollController,
    required this.coverUri,
    required this.onPlay,
  });

  final LibraryController controller;
  final ScrollController scrollController;
  final Uri Function(String trackId) coverUri;
  final ValueChanged<Track> onPlay;

  @override
  Widget build(BuildContext context) {
    if (controller.isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null && controller.items.isEmpty) {
      return _MessageState(
        icon: Icons.cloud_off,
        message: controller.error!,
        actionLabel: 'Retry',
        onAction: controller.retry,
      );
    }
    if (controller.isEmpty) {
      return _MessageState(
        icon: Icons.library_music_outlined,
        message: controller.query.isEmpty
            ? 'Your library is empty.'
            : 'No tracks match “${controller.query}”.',
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView.builder(
          key: const Key('track-list'),
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          itemCount: controller.items.length + 1,
          itemBuilder: (context, index) {
            if (index == controller.items.length) {
              if (controller.isLoadingMore) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (controller.error != null) {
                return Center(
                  child: TextButton.icon(
                    onPressed: controller.loadMore,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry loading more'),
                  ),
                );
              }
              if (controller.hasMore) {
                return Center(
                  child: TextButton(
                    key: const Key('load-more-button'),
                    onPressed: controller.loadMore,
                    child: const Text('Load more'),
                  ),
                );
              }
              return const SizedBox(height: 8);
            }
            final track = controller.items[index];
            return _TrackTile(
              track: track,
              coverUri: coverUri,
              onPlay: () => onPlay(track),
            );
          },
        ),
      ),
    );
  }
}

final class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.coverUri,
    required this.onPlay,
  });

  final Track track;
  final Uri Function(String trackId) coverUri;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: SizedBox.square(
          dimension: 52,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: track.hasCover
                ? Image.network(
                    coverUri(track.id).toString(),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _CoverPlaceholder(),
                  )
                : const _CoverPlaceholder(),
          ),
        ),
        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${track.artist} • ${track.album}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(track.formattedDuration),
            IconButton(
              tooltip: 'Play ${track.title}',
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow),
            ),
          ],
        ),
        onTap: onPlay,
      ),
    );
  }
}

final class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Center(child: Icon(Icons.music_note)),
  );
}

final class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}
