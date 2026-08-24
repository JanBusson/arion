import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../configuration/api_base_url.dart';
import 'track.dart';

abstract interface class CatalogApi {
  Future<TrackPage> fetchTracks({
    int limit = 30,
    int offset = 0,
    String? query,
  });

  Uri coverUri(String trackId);
  Uri audioUri(String trackId);
  void close();
}

final class CatalogException implements Exception {
  const CatalogException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class ArionApi implements CatalogApi {
  ArionApi({
    required this.baseUrl,
    required this.client,
    this.timeout = const Duration(seconds: 10),
  });

  final ApiBaseUrl baseUrl;
  final http.Client client;
  final Duration timeout;

  @override
  Future<TrackPage> fetchTracks({
    int limit = 30,
    int offset = 0,
    String? query,
  }) async {
    final parameters = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (query?.trim().isNotEmpty == true) 'q': query!.trim(),
    };
    final uri = baseUrl
        .endpoint('/api/v1/tracks')
        .replace(queryParameters: parameters);
    try {
      final response = await client.get(uri).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const CatalogException('The server could not load the library.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Catalog response must be an object.');
      }
      return TrackPage.fromJson(decoded);
    } on TimeoutException {
      throw const CatalogException('The server took too long to respond.');
    } on FormatException {
      throw const CatalogException('The server returned invalid catalog data.');
    } on CatalogException {
      rethrow;
    } on Object {
      throw const CatalogException('The server could not be reached.');
    }
  }

  @override
  Uri coverUri(String trackId) =>
      baseUrl.endpoint('/api/v1/tracks/$trackId/cover');

  @override
  Uri audioUri(String trackId) =>
      baseUrl.endpoint('/api/v1/tracks/$trackId/audio');

  @override
  void close() => client.close();
}
