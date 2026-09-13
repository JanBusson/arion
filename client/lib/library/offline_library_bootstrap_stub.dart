import '../configuration/api_base_url.dart';
import '../playback/offline_audio_resolver.dart';
import 'offline_library.dart';

OfflineLibraryController createDefaultOfflineLibraryController(
  ApiBaseUrl baseUrl,
) => NoopOfflineLibraryController();

OfflineAudioResolver createDefaultOfflineAudioResolver() =>
    const NoopOfflineAudioResolver();
