import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../configuration/api_base_url.dart';
import '../playback/offline_audio_resolver.dart';
import 'catalog_api.dart';
import 'offline_library.dart';
import 'offline_library_io.dart';

OfflineLibraryController createDefaultOfflineLibraryController(
  ApiBaseUrl baseUrl,
) {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return NoopOfflineLibraryController();
  }
  return AndroidOfflineLibraryController(
    baseUrl: baseUrl,
    catalogApi: ArionApi(baseUrl: baseUrl, client: http.Client()),
    downloadClient: http.Client(),
  );
}

OfflineAudioResolver createDefaultOfflineAudioResolver() =>
    defaultTargetPlatform == TargetPlatform.android
    ? AndroidOfflineAudioResolver()
    : const NoopOfflineAudioResolver();
