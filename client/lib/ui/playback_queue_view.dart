import 'package:flutter/material.dart';

import '../playback/playback_controller.dart';

Future<void> showPlaybackQueue(
  BuildContext context,
  PlaybackController controller,
) async {
  if (MediaQuery.sizeOf(context).width < 700) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.75,
        child: PlaybackQueueView(controller: controller),
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: SizedBox(
        width: 560,
        height: 620,
        child: PlaybackQueueView(
          controller: controller,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    ),
  );
}

final class PlaybackQueueView extends StatelessWidget {
  const PlaybackQueueView({required this.controller, this.onClose, super.key});

  final PlaybackController controller;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final current = controller.currentEntry;
        final upcoming = controller.upcomingEntries;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Playback queue',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  if (onClose != null)
                    IconButton(
                      tooltip: 'Close queue',
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (current == null)
                const Expanded(
                  child: Center(
                    child: Text(
                      'The playback queue is empty.',
                      key: Key('queue-empty-state'),
                    ),
                  ),
                )
              else ...[
                Text(
                  'Now playing',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Card(
                  key: Key('queue-current-${current.id}'),
                  child: ListTile(
                    leading: const Icon(Icons.volume_up_outlined),
                    title: Text(
                      current.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      current.track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Up next', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Expanded(
                  child: upcoming.isEmpty
                      ? const Center(child: Text('Nothing is queued next.'))
                      : ReorderableListView.builder(
                          key: const Key('upcoming-queue-list'),
                          buildDefaultDragHandles: false,
                          itemCount: upcoming.length,
                          onReorderItem: (oldIndex, newIndex) {
                            controller.moveUpcoming(
                              upcoming[oldIndex].id,
                              newIndex,
                            );
                          },
                          itemBuilder: (context, index) {
                            final entry = upcoming[index];
                            return Card(
                              key: ValueKey('queue-entry-${entry.id}'),
                              child: ListTile(
                                leading: ReorderableDragStartListener(
                                  index: index,
                                  child: const Tooltip(
                                    message: 'Reorder queued track',
                                    child: Icon(Icons.drag_handle),
                                  ),
                                ),
                                title: Text(
                                  entry.track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  entry.track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: IconButton(
                                  key: Key('remove-queue-entry-${entry.id}'),
                                  tooltip:
                                      'Remove ${entry.track.title} from queue',
                                  onPressed: () =>
                                      controller.removeUpcoming(entry.id),
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}
