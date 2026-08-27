import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../library/acquisition.dart';
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

  Future<void> _confirmAcquisition(YouTubeCandidate candidate) async {
    var acknowledged = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Experimental YouTube acquisition'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${candidate.title} — ${candidate.channel}'),
                const SizedBox(height: 12),
                const Text(
                  'YouTube may restrict downloading. This confirmation does '
                  'not grant rights or override provider terms.',
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  key: const Key('acquisition-authorization-checkbox'),
                  contentPadding: EdgeInsets.zero,
                  value: acknowledged,
                  onChanged: (value) =>
                      setDialogState(() => acknowledged = value ?? false),
                  title: const Text(
                    'I confirm that I am authorized to acquire this content.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm-acquisition-button'),
              onPressed: acknowledged
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: const Text('Acquire'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      await widget.library.startAcquisition(candidate);
    }
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
                child: ListenableBuilder(
                  listenable: widget.library,
                  builder: (context, _) => _SearchControls(
                    controller: _search,
                    library: widget.library,
                    onClear: _clearSearch,
                  ),
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
                  onDiscoverYouTube: widget.library.discoverYouTube,
                  onSelectCandidate: _confirmAcquisition,
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

final class _SearchControls extends StatelessWidget {
  const _SearchControls({
    required this.controller,
    required this.library,
    required this.onClear,
  });

  final TextEditingController controller;
  final LibraryController library;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final search = TextField(
        key: const Key('library-search-field'),
        controller: controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search title, artist, or album',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: 'Clear search',
            onPressed: onClear,
            icon: const Icon(Icons.clear),
          ),
          border: const OutlineInputBorder(),
        ),
        onSubmitted: library.submitSearch,
      );
      final modes = _DiscoveryModeChoices(
        value: library.discoveryMode,
        onChanged: library.setDiscoveryMode,
      );
      if (constraints.maxWidth >= 640) {
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 12),
            modes,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [search, const SizedBox(height: 4), modes],
      );
    },
  );
}

final class _DiscoveryModeChoices extends StatelessWidget {
  const _DiscoveryModeChoices({required this.value, required this.onChanged});

  final YouTubeDiscoveryMode value;
  final ValueChanged<YouTubeDiscoveryMode> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'External search source',
    container: true,
    child: RadioGroup<YouTubeDiscoveryMode>(
      groupValue: value,
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
      child: Wrap(
        key: const Key('youtube-discovery-mode-controls'),
        spacing: 4,
        children: [
          _choice(YouTubeDiscoveryMode.music, 'Music'),
          _choice(YouTubeDiscoveryMode.all, 'All'),
        ],
      ),
    ),
  );

  Widget _choice(YouTubeDiscoveryMode mode, String label) => InkWell(
    key: Key('youtube-mode-${mode.wireValue}'),
    borderRadius: BorderRadius.circular(20),
    onTap: () => onChanged(mode),
    child: Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Radio<YouTubeDiscoveryMode>(value: mode),
          Text(label),
        ],
      ),
    ),
  );
}

final class _LibraryBody extends StatelessWidget {
  const _LibraryBody({
    required this.controller,
    required this.scrollController,
    required this.coverUri,
    required this.onPlay,
    required this.onDiscoverYouTube,
    required this.onSelectCandidate,
  });

  final LibraryController controller;
  final ScrollController scrollController;
  final Uri Function(String trackId) coverUri;
  final ValueChanged<Track> onPlay;
  final VoidCallback onDiscoverYouTube;
  final ValueChanged<YouTubeCandidate> onSelectCandidate;

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
    final job = controller.activeJob;
    if (job?.isActive == true && controller.items.isEmpty) {
      return _AcquisitionStatus(job: job!, error: controller.acquisitionError);
    }
    if (controller.isEmpty) {
      if (controller.isDiscovering) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.candidates.isNotEmpty) {
        return _CandidateList(
          candidates: controller.candidates,
          mode: controller.discoveryMode,
          onSelect: onSelectCandidate,
        );
      }
      if (controller.acquisitionError != null) {
        return _MessageState(
          icon: Icons.download_for_offline_outlined,
          message: controller.acquisitionError!,
          actionLabel: controller.canSearchYouTube
              ? controller.discoveryRetryLabel
              : null,
          onAction: controller.canSearchYouTube ? onDiscoverYouTube : null,
        );
      }
      return _MessageState(
        icon: Icons.library_music_outlined,
        message: controller.query.isEmpty
            ? 'Your library is empty.'
            : 'No tracks match “${controller.query}”.',
        actionLabel: controller.canSearchYouTube
            ? controller.discoveryActionLabel
            : null,
        onAction: controller.canSearchYouTube ? onDiscoverYouTube : null,
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          children: [
            if (job != null)
              _AcquisitionStatus(
                job: job,
                error: controller.acquisitionError,
                compact: true,
              ),
            Expanded(
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
          ],
        ),
      ),
    );
  }
}

final class _CandidateList extends StatelessWidget {
  const _CandidateList({
    required this.candidates,
    required this.mode,
    required this.onSelect,
  });

  final List<YouTubeCandidate> candidates;
  final YouTubeDiscoveryMode mode;
  final ValueChanged<YouTubeCandidate> onSelect;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 960),
      child: ListView.builder(
        key: const Key('youtube-candidate-list'),
        padding: const EdgeInsets.all(12),
        itemCount: candidates.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: Text(
                mode == YouTubeDiscoveryMode.music
                    ? 'YouTube Music song results'
                    : 'All YouTube results',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            );
          }
          final candidate = candidates[index - 1];
          return Card(
            child: ListTile(
              leading: SizedBox.square(
                dimension: 72,
                child: candidate.thumbnailUrl == null
                    ? const _CoverPlaceholder()
                    : Image.network(
                        candidate.thumbnailUrl.toString(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _CoverPlaceholder(),
                      ),
              ),
              title: Text(candidate.title),
              subtitle: Text(
                '${mode == YouTubeDiscoveryMode.music ? 'Artist' : 'Channel'}: '
                '${candidate.channel} • ${candidate.formattedDuration}',
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Open on YouTube',
                    onPressed: () => launchUrl(
                      candidate.pageUrl,
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new),
                  ),
                  FilledButton(
                    key: Key('select-candidate-${candidate.videoId}'),
                    onPressed: () => onSelect(candidate),
                    child: const Text('Select'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

final class _AcquisitionStatus extends StatelessWidget {
  const _AcquisitionStatus({
    required this.job,
    required this.error,
    this.compact = false,
  });

  final AcquisitionJob job;
  final String? error;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Card(
      key: const Key('acquisition-status'),
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              job.candidate.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              job.isCompleted ? 'Ready in your library' : error ?? job.phase,
            ),
            if (job.isActive) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: job.progressPercent / 100),
            ],
          ],
        ),
      ),
    );
    return compact
        ? content
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: content,
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
