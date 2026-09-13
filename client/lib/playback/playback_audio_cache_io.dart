import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../configuration/resource_identity.dart';
import 'playback_audio_cache.dart';

const arionPlaybackCacheMaxBytes = 1024 * 1024 * 1024;

typedef PlaybackCacheDirectoryProvider = Future<Directory> Function();
typedef PlaybackCacheClock = DateTime Function();

PlaybackAudioCache createAndroidPlaybackCache() => PlaybackCacheManager(
  rootDirectory: () async {
    final base = await getTemporaryDirectory();
    return Directory(_childPath(base.path, 'arion_playback_cache'));
  },
);

final class PlaybackCacheEntryPaths {
  const PlaybackCacheEntryPaths({
    required this.key,
    required this.directory,
    required this.mediaFile,
    required this.partialFile,
    required this.mimeFile,
  });

  final String key;
  final Directory directory;
  final File mediaFile;
  final File partialFile;
  final File mimeFile;
}

final class PlaybackCacheManager implements PlaybackAudioCache {
  PlaybackCacheManager({
    required PlaybackCacheDirectoryProvider rootDirectory,
    this.maxBytes = arionPlaybackCacheMaxBytes,
    PlaybackCacheClock? clock,
  }) : _rootDirectoryProvider = rootDirectory,
       _clock = clock ?? DateTime.now;

  final PlaybackCacheDirectoryProvider _rootDirectoryProvider;
  final PlaybackCacheClock _clock;
  final int maxBytes;

  Future<void> _tail = Future.value();
  Directory? _root;
  String? _protectedKey;
  bool _disposed = false;

  static String keyFor(Uri uri) => resourceKey(uri);

  Future<PlaybackCacheEntryPaths> pathsFor(Uri uri) async {
    final root = _root ?? await _rootDirectoryProvider();
    return _paths(root, keyFor(uri));
  }

  @override
  Future<PlaybackCacheSource?> prepare(
    Uri uri, {
    bool bypassCompleteCache = false,
  }) async {
    if (_disposed) return null;
    try {
      return await _enqueue(() async {
        final key = keyFor(uri);
        _protectedKey = key;
        final root = await _initialize();
        final paths = _paths(root, key);
        if (bypassCompleteCache && await paths.directory.exists()) {
          await paths.directory.delete(recursive: true);
        }
        if (await paths.mediaFile.exists()) {
          if (await paths.mediaFile.length() > 0) {
            await _touch(paths.mediaFile);
            return PlaybackCacheSource(
              key: key,
              source: AudioSource.file(paths.mediaFile.path),
              fromCompleteCache: true,
              completion: const Stream<void>.empty(),
            );
          }
          await paths.directory.delete(recursive: true);
        }
        await paths.directory.create(recursive: true);
        // ignore: experimental_member_use
        final source = LockCachingAudioSource(uri, cacheFile: paths.mediaFile);
        return PlaybackCacheSource(
          key: key,
          source: source,
          fromCompleteCache: false,
          completion: source.downloadProgressStream
              .where((progress) => progress >= 1)
              .take(1)
              .map((_) {}),
        );
      });
    } on Object {
      return null;
    }
  }

  @override
  Future<void> complete(String key) async {
    if (_disposed) return;
    try {
      await _enqueue(() async {
        final root = await _initialize();
        final paths = _paths(root, key);
        for (var attempt = 0; attempt < 100; attempt += 1) {
          if (await paths.mediaFile.exists()) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        if (await paths.mediaFile.exists() &&
            await paths.mediaFile.length() > 0) {
          await _touch(paths.mediaFile);
        }
        await _cleanupAndPrune(root);
      });
    } on Object {
      // Cache completion is opportunistic and must not interrupt playback.
    }
  }

  @override
  Future<int?> exportComplete(Uri uri, String destinationPath) async {
    if (_disposed) return null;
    try {
      return await _enqueue(() async {
        final root = await _initialize();
        final source = _paths(root, keyFor(uri)).mediaFile;
        if (!await source.exists()) return null;
        final length = await source.length();
        if (length <= 0) return null;
        final destination = File(destinationPath);
        await destination.parent.create(recursive: true);
        final temporary = File('$destinationPath.cache-copy');
        if (await temporary.exists()) await temporary.delete();
        await source.copy(temporary.path);
        if (await temporary.length() != length) {
          await temporary.delete();
          return null;
        }
        if (await destination.exists()) await destination.delete();
        await temporary.rename(destination.path);
        return length;
      });
    } on Object {
      return null;
    }
  }

  @override
  Future<void> invalidate(String key) async {
    if (_disposed) return;
    try {
      await _enqueue(() async {
        final root = await _initialize();
        final directory = _paths(root, key).directory;
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
        if (_protectedKey == key) _protectedKey = null;
      });
    } on Object {
      // A failed invalidation is handled by bypassing cache for the next load.
    }
  }

  @override
  Future<void> release() async {
    if (_disposed) return;
    try {
      await _enqueue(() async {
        _protectedKey = null;
        final root = await _initialize();
        await _cleanupAndPrune(root);
      });
    } on Object {
      // Cache cleanup must not make source replacement fail.
    }
  }

  @override
  Future<void> maintain() async {
    if (_disposed) return;
    try {
      await _enqueue(() async {
        final root = await _initialize();
        await _cleanupAndPrune(root);
      });
    } on Object {
      // Explicit maintenance has the same fail-open behavior as lazy cleanup.
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await _tail.catchError((Object _) {});
    _protectedKey = null;
    _disposed = true;
  }

  Future<Directory> _initialize() async {
    final existing = _root;
    if (existing != null) return existing;
    final root = await _rootDirectoryProvider();
    await root.create(recursive: true);
    _root = root;
    await _cleanupAndPrune(root);
    return root;
  }

  Future<void> _cleanupAndPrune(Directory root) async {
    if (!await root.exists()) return;
    final candidates = <_CacheCandidate>[];
    var totalBytes = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) {
        await entity.delete(recursive: true);
        continue;
      }
      final key = _basename(entity.path);
      final paths = _paths(root, key);
      final bytes = await _directoryBytes(entity);
      final complete =
          await paths.mediaFile.exists() && await paths.mediaFile.length() > 0;
      if (!complete && key != _protectedKey) {
        await entity.delete(recursive: true);
        continue;
      }
      totalBytes += bytes;
      if (complete && key != _protectedKey) {
        final modified = await paths.mediaFile.lastModified();
        candidates.add(
          _CacheCandidate(directory: entity, bytes: bytes, modified: modified),
        );
      }
    }
    candidates.sort((left, right) => left.modified.compareTo(right.modified));
    for (final candidate in candidates) {
      if (totalBytes <= maxBytes) break;
      await candidate.directory.delete(recursive: true);
      totalBytes -= candidate.bytes;
    }
  }

  Future<void> _touch(File file) => file.setLastModified(_clock());

  Future<int> _directoryBytes(Directory directory) async {
    var bytes = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) bytes += await entity.length();
    }
    return bytes;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  static PlaybackCacheEntryPaths _paths(Directory root, String key) {
    final directory = Directory(_childPath(root.path, key));
    final mediaPath = _childPath(directory.path, 'audio.bin');
    return PlaybackCacheEntryPaths(
      key: key,
      directory: directory,
      mediaFile: File(mediaPath),
      partialFile: File('$mediaPath.part'),
      mimeFile: File('$mediaPath.mime'),
    );
  }
}

final class _CacheCandidate {
  const _CacheCandidate({
    required this.directory,
    required this.bytes,
    required this.modified,
  });

  final Directory directory;
  final int bytes;
  final DateTime modified;
}

String _childPath(String parent, String child) =>
    '$parent${Platform.pathSeparator}$child';

String _basename(String path) {
  final normalized = path.endsWith(Platform.pathSeparator)
      ? path.substring(0, path.length - 1)
      : path;
  return normalized.substring(
    normalized.lastIndexOf(Platform.pathSeparator) + 1,
  );
}
