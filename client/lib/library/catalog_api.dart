import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../configuration/api_base_url.dart';
import 'acquisition.dart';
import 'track.dart';

abstract interface class CatalogApi {
  Future<TrackPage> fetchTracks({
    int limit = 30,
    int offset = 0,
    String? query,
  });

  Future<Track> fetchTrack(String trackId);
  Future<List<YouTubeCandidate>> discoverYouTube(
    String query,
    YouTubeDiscoveryMode mode,
  );
  Future<AcquisitionJob> createAcquisitionJob(String candidateId);
  Future<AcquisitionJob> fetchAcquisitionJob(String jobId);

  Uri coverUri(String trackId);
  Uri audioUri(String trackId);
  void close();
}

final class CatalogException implements Exception {
  const CatalogException(this.message, {this.code});

  final String message;
  final String? code;

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
  Future<Track> fetchTrack(String trackId) async {
    final decoded = await _getObject(
      baseUrl.endpoint('/api/v1/tracks/$trackId'),
      invalidMessage: 'The server returned invalid track data.',
    );
    return Track.fromJson(decoded);
  }

  @override
  Future<List<YouTubeCandidate>> discoverYouTube(
    String query,
    YouTubeDiscoveryMode mode,
  ) async {
    final uri = baseUrl
        .endpoint('/api/v1/acquisition/youtube/candidates')
        .replace(queryParameters: {'q': query.trim(), 'mode': mode.wireValue});
    final decoded = await _getObject(
      uri,
      invalidMessage: 'The server returned invalid candidate data.',
    );
    final items = decoded['items'];
    if (items is! List<Object?>) {
      throw const CatalogException(
        'The server returned invalid candidate data.',
      );
    }
    try {
      final candidates = items
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Candidate must be an object.');
            }
            return YouTubeCandidate.fromJson(item);
          })
          .toList(growable: false);
      if (candidates.any((candidate) => candidate.discoveryMode != mode)) {
        throw const FormatException('Candidate mode does not match request.');
      }
      return candidates;
    } on FormatException {
      throw const CatalogException(
        'The server returned invalid candidate data.',
      );
    }
  }

  @override
  Future<AcquisitionJob> createAcquisitionJob(String candidateId) async {
    final uri = baseUrl.endpoint('/api/v1/acquisition/jobs');
    try {
      final response = await client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'candidate_id': candidateId,
              'authorization_acknowledged': true,
            }),
          )
          .timeout(timeout);
      final decoded = _decodeResponse(response);
      return AcquisitionJob.fromJson(decoded);
    } on TimeoutException {
      throw const CatalogException('The server took too long to respond.');
    } on CatalogException {
      rethrow;
    } on FormatException {
      throw const CatalogException('The server returned invalid job data.');
    } on Object {
      throw const CatalogException('The server could not be reached.');
    }
  }

  @override
  Future<AcquisitionJob> fetchAcquisitionJob(String jobId) async {
    final decoded = await _getObject(
      baseUrl.endpoint('/api/v1/acquisition/jobs/$jobId'),
      invalidMessage: 'The server returned invalid job data.',
    );
    try {
      return AcquisitionJob.fromJson(decoded);
    } on FormatException {
      throw const CatalogException('The server returned invalid job data.');
    }
  }

  Future<Map<String, Object?>> _getObject(
    Uri uri, {
    required String invalidMessage,
  }) async {
    try {
      final response = await client.get(uri).timeout(timeout);
      return _decodeResponse(response);
    } on TimeoutException {
      throw const CatalogException('The server took too long to respond.');
    } on CatalogException {
      rethrow;
    } on FormatException {
      throw CatalogException(invalidMessage);
    } on Object {
      throw const CatalogException('The server could not be reached.');
    }
  }

  Map<String, Object?> _decodeResponse(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      if (response.statusCode >= 200 && response.statusCode < 300) rethrow;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? code;
      String? message;
      if (decoded is Map<String, Object?>) {
        final detail = decoded['detail'];
        if (detail is Map<String, Object?>) {
          code = detail['code'] is String ? detail['code'] as String : null;
          message = detail['message'] is String
              ? detail['message'] as String
              : null;
        }
      }
      throw CatalogException(
        message ?? 'The server could not complete the request.',
        code: code,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Response must be an object.');
    }
    return decoded;
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
