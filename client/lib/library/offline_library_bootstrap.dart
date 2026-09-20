import '../configuration/api_base_url.dart';
import '../playback/offline_audio_resolver.dart';
import 'offline_library.dart';
import 'offline_library_bootstrap_stub.dart'
    if (dart.library.io) 'offline_library_bootstrap_io.dart'
    as platform;

OfflineLibraryController createDefaultOfflineLibraryController(
  ApiBaseUrl baseUrl,
) => platform.createDefaultOfflineLibraryController(baseUrl);

OfflineAudioResolver createDefaultOfflineAudioResolver() =>
    platform.createDefaultOfflineAudioResolver();
