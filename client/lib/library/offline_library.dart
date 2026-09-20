import 'package:flutter/foundation.dart';

import 'track.dart';

const offlineCatalogVersion = 1;

final class OfflineCatalogSnapshot {
  const OfflineCatalogSnapshot({
    required this.serverUrl,
    required this.savedAt,
    required this.tracks,
    this.version = offlineCatalogVersion,
  });

  factory OfflineCatalogSnapshot.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version != offlineCatalogVersion) {
      throw const FormatException('Unsupported offline catalog version.');
    }
    final serverUrl = json['server_url'];
    final savedAt = json['saved_at'];
    final rawTracks = json['tracks'];
    if (serverUrl is! String || savedAt is! String || rawTracks is! List) {
      throw const FormatException('Invalid offline catalog.');
    }
    final parsedSavedAt = DateTime.tryParse(savedAt);
    if (parsedSavedAt == null) {
      throw const FormatException('Invalid offline catalog timestamp.');
    }
    return OfflineCatalogSnapshot(
      version: version as int,
      serverUrl: serverUrl,
      savedAt: parsedSavedAt,
      tracks: rawTracks
          .map((value) {
            if (value is! Map) {
              throw const FormatException('Invalid offline track.');
            }
            return Track.fromJson(Map<String, Object?>.from(value));
          })
          .toList(growable: false),
    );
  }

  final int version;
  final String serverUrl;
  final DateTime savedAt;
  final List<Track> tracks;

  Map<String, Object?> toJson() => {
    'version': version,
    'server_url': serverUrl,
    'saved_at': savedAt.toUtc().toIso8601String(),
    'tracks': tracks.map((track) => track.toJson()).toList(growable: false),
  };
}

enum OfflineLibraryPhase { disabled, preparing, ready, unavailable, failed }

abstract interface class OfflineCatalogSnapshotStore {
  Future<OfflineCatalogSnapshot?> loadSnapshot();
}

abstract class OfflineLibraryController extends ChangeNotifier
    implements OfflineCatalogSnapshotStore {
  bool get isSupported;
  bool get isEnabled;
  OfflineLibraryPhase get phase;
  int get completedCount;
  int get totalCount;
  int get activeCount;
  String? get error;
  Set<String> get readyTrackIds;

  bool isTrackReady(String trackId) => readyTrackIds.contains(trackId);

  Future<void> initialize();
  Future<void> enable();
  Future<void> disable();
  Future<void> synchronize();
  Future<void> retry();
}

final class NoopOfflineLibraryController extends OfflineLibraryController {
  @override
  bool get isSupported => false;

  @override
  bool get isEnabled => false;

  @override
  OfflineLibraryPhase get phase => OfflineLibraryPhase.disabled;

  @override
  int get completedCount => 0;

  @override
  int get totalCount => 0;

  @override
  int get activeCount => 0;

  @override
  String? get error => null;

  @override
  Set<String> get readyTrackIds => const {};

  @override
  Future<OfflineCatalogSnapshot?> loadSnapshot() async => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}

  @override
  Future<void> synchronize() async {}

  @override
  Future<void> retry() async {}
}
