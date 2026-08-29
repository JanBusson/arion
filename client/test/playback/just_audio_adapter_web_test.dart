@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';

import 'package:arion_client/playback/audio_player_port.dart';
import 'package:arion_client/playback/just_audio_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _fixtureUrl = String.fromEnvironment('ARION_AUDIO_FIXTURE_URL');

void main() {
  test(
    'requests and loads a distinct ranged source in Chrome',
    () async {
      await http.get(Uri.parse('$_fixtureUrl/reset'));
      final first = RangeRequestAudioEngine();
      final second = RangeRequestAudioEngine();
      final adapter = JustAudioAdapter(
        engine: first,
        engineFactory: () => second,
      );
      addTearDown(adapter.dispose);

      final firstDuration = await adapter.setUrl(
        Uri.parse('$_fixtureUrl/audio/first.wav'),
      );
      await adapter.play();
      final secondDuration = await adapter.setUrl(
        Uri.parse('$_fixtureUrl/audio/second.wav'),
      );

      expect(firstDuration, const Duration(seconds: 1));
      expect(secondDuration, const Duration(milliseconds: 1600));
      expect(first.stopCalls, 1);
      expect(first.disposed, isTrue);
      expect(second.currentUrl.path, '/audio/second.wav');

      final requests = await _audioRequests();
      expect(
        requests.map((request) => request.path),
        containsAll(['/audio/first.wav', '/audio/second.wav']),
      );
      expect(requests.every((request) => request.byteRange != null), isTrue);
    },
    skip: _fixtureUrl.isEmpty
        ? 'Set ARION_AUDIO_FIXTURE_URL for the Chrome integration fixture.'
        : false,
  );

  test(
    'keeps the newest ranged source during rapid browser replacement',
    () async {
      await http.get(Uri.parse('$_fixtureUrl/reset'));
      final first = RangeRequestAudioEngine();
      final second = RangeRequestAudioEngine();
      final adapter = JustAudioAdapter(
        engine: first,
        engineFactory: () => second,
      );
      addTearDown(adapter.dispose);

      final obsolete = adapter.setUrl(
        Uri.parse('$_fixtureUrl/audio/first.wav?delay_ms=500'),
      );
      final obsoleteExpectation = expectLater(
        obsolete,
        throwsA(isA<AudioSourceSupersededException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final latestDuration = await adapter.setUrl(
        Uri.parse('$_fixtureUrl/audio/second.wav'),
      );

      await obsoleteExpectation;
      expect(latestDuration, const Duration(milliseconds: 1600));
      expect(second.currentUrl.path, '/audio/second.wav');
      final requests = await _audioRequests();
      expect(requests.last.path, '/audio/second.wav');
    },
    skip: _fixtureUrl.isEmpty
        ? 'Set ARION_AUDIO_FIXTURE_URL for the Chrome integration fixture.'
        : false,
  );

  test(
    'requests the replacement source when the first source is paused',
    () async {
      await http.get(Uri.parse('$_fixtureUrl/reset'));
      final first = RangeRequestAudioEngine();
      final second = RangeRequestAudioEngine();
      final adapter = JustAudioAdapter(
        engine: first,
        engineFactory: () => second,
      );
      addTearDown(adapter.dispose);

      await adapter.setUrl(Uri.parse('$_fixtureUrl/audio/first.wav'));
      await adapter.play();
      await adapter.pause();
      final secondDuration = await adapter.setUrl(
        Uri.parse('$_fixtureUrl/audio/second.wav'),
      );

      expect(secondDuration, const Duration(milliseconds: 1600));
      expect(first.stopCalls, 1);
      expect(first.disposed, isTrue);
      expect(second.currentUrl.path, '/audio/second.wav');
      final requests = await _audioRequests();
      expect(requests.last.path, '/audio/second.wav');
      expect(requests.last.byteRange, 'bytes=0-1023');
    },
    skip: _fixtureUrl.isEmpty
        ? 'Set ARION_AUDIO_FIXTURE_URL for the Chrome integration fixture.'
        : false,
  );
}

final class RangeRequestAudioEngine implements AudioPlayerEngine {
  final StreamController<bool> _playing = StreamController.broadcast();
  final StreamController<AudioProcessingState> _processing =
      StreamController.broadcast();
  final StreamController<Duration> _positions = StreamController.broadcast();
  final StreamController<Duration?> _durations = StreamController.broadcast();
  final StreamController<Object> _errors = StreamController.broadcast();
  final http.Client _client = http.Client();

  Uri currentUrl = Uri();
  int stopCalls = 0;
  bool disposed = false;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<AudioProcessingState> get processingStateStream => _processing.stream;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration?> get durationStream => _durations.stream;

  @override
  Stream<Object> get errorStream => _errors.stream;

  @override
  Future<Duration?> setUrl(Uri uri) async {
    currentUrl = uri;
    final response = await _client.get(
      uri,
      headers: const {'Range': 'bytes=0-1023'},
    );
    if (response.statusCode != 206) {
      throw StateError('Expected a ranged audio response.');
    }
    final duration = Duration(
      milliseconds: int.parse(response.headers['x-arion-test-duration-ms']!),
    );
    _processing.add(AudioProcessingState.ready);
    _durations.add(duration);
    return duration;
  }

  @override
  Future<void> play() async => _playing.add(true);

  @override
  Future<void> pause() async => _playing.add(false);

  @override
  Future<void> stop() async {
    stopCalls += 1;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async => _positions.add(position);

  @override
  Future<void> dispose() async {
    disposed = true;
    _client.close();
  }
}

Future<List<({String path, String? byteRange})>> _audioRequests() async {
  final response = await http.get(Uri.parse('$_fixtureUrl/requests'));
  expect(response.statusCode, 200);
  final payload = jsonDecode(response.body) as Map<String, dynamic>;
  final requests = payload['requests'] as List<dynamic>;
  return requests.cast<Map<String, dynamic>>().map((request) {
    return (
      path: request['path']! as String,
      byteRange: request['range'] as String?,
    );
  }).toList();
}
