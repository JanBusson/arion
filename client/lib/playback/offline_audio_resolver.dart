final class OfflineAudioFile {
  const OfflineAudioFile({
    required this.key,
    required this.path,
    required this.length,
  });

  final String key;
  final String path;
  final int length;
}

abstract interface class OfflineAudioResolver {
  Future<OfflineAudioFile?> resolve(Uri uri);
  Future<void> invalidate(Uri uri);
  Future<void> dispose();
}

final class NoopOfflineAudioResolver implements OfflineAudioResolver {
  const NoopOfflineAudioResolver();

  @override
  Future<OfflineAudioFile?> resolve(Uri uri) async => null;

  @override
  Future<void> invalidate(Uri uri) async {}

  @override
  Future<void> dispose() async {}
}
