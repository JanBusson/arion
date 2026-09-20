import 'dart:async';

import 'package:flutter/material.dart';

import 'configuration/api_base_url.dart';
import 'configuration/settings_controller.dart';
import 'configuration/settings_store.dart';
import 'library/catalog_api.dart';
import 'library/acquisition_job_store.dart';
import 'library/library_controller.dart';
import 'library/offline_library.dart';
import 'playback/audio_player_port.dart';
import 'playback/playback_controller.dart';
import 'playback/playback_session_coordinator.dart';
import 'ui/library_screen.dart';
import 'ui/settings_screen.dart';

typedef CatalogApiFactory = CatalogApi Function(ApiBaseUrl baseUrl);
typedef AudioPlayerFactory = AudioPlayerPort Function();
typedef OfflineLibraryFactory =
    OfflineLibraryController Function(ApiBaseUrl baseUrl);

final class ArionApp extends StatefulWidget {
  const ArionApp({
    required this.settingsStore,
    required this.catalogApiFactory,
    required this.audioPlayerFactory,
    this.playbackSession,
    this.acquisitionJobStore,
    this.offlineLibraryFactory,
    this.seedBaseUrl = const String.fromEnvironment('ARION_API_BASE_URL'),
    super.key,
  });

  final SettingsStore settingsStore;
  final CatalogApiFactory catalogApiFactory;
  final AudioPlayerFactory audioPlayerFactory;
  final PlaybackSessionCoordinator? playbackSession;
  final AcquisitionJobStore? acquisitionJobStore;
  final OfflineLibraryFactory? offlineLibraryFactory;
  final String seedBaseUrl;

  @override
  State<ArionApp> createState() => _ArionAppState();
}

final class _ArionAppState extends State<ArionApp> {
  late final SettingsController _settings;
  late final AcquisitionJobStore _jobStore;
  late final PlaybackSessionCoordinator _playbackSession;
  late final bool _ownsPlaybackSession;
  _ClientSession? _session;
  int _replacementGeneration = 0;

  @override
  void initState() {
    super.initState();
    _settings = SettingsController(
      widget.settingsStore,
      seedBaseUrl: widget.seedBaseUrl,
    );
    _jobStore = widget.acquisitionJobStore ?? MemoryAcquisitionJobStore();
    _ownsPlaybackSession = widget.playbackSession == null;
    _playbackSession =
        widget.playbackSession ??
        PlaybackSessionCoordinator(
          createAudioPlayer: widget.audioPlayerFactory,
        );
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _playbackSession.initialize();
    await _settings.load();
    if (!mounted) {
      return;
    }
    await _replaceSession(_settings.baseUrl);
  }

  Future<bool> _saveServer(String value) async {
    final saved = await _settings.save(value);
    if (saved && mounted) {
      await _replaceSession(_settings.baseUrl);
    }
    return saved;
  }

  Future<void> _replaceSession(ApiBaseUrl? baseUrl) async {
    final generation = ++_replacementGeneration;
    final oldSession = _session;
    setState(() {
      _session = null;
    });
    if (oldSession != null &&
        baseUrl != null &&
        oldSession.baseUrl.toString() != baseUrl.toString()) {
      await oldSession.offline.disable();
    }
    oldSession?.dispose();
    final playback = await _playbackSession.replaceSession(
      configured: baseUrl != null,
    );
    if (!mounted || generation != _replacementGeneration) return;
    if (baseUrl == null || playback == null) return;
    final offline =
        widget.offlineLibraryFactory?.call(baseUrl) ??
        NoopOfflineLibraryController();
    await offline.initialize();
    if (!mounted || generation != _replacementGeneration) {
      offline.dispose();
      return;
    }
    final library = LibraryController(
      widget.catalogApiFactory(baseUrl),
      jobStore: _jobStore,
      snapshotStore: offline,
      onUnfilteredCatalogChanged: () => unawaited(offline.synchronize()),
    );
    setState(() {
      _session = _ClientSession(
        baseUrl: baseUrl,
        library: library,
        playback: playback,
        offline: offline,
      );
    });
  }

  Future<void> _showSettings(BuildContext dialogContext) async {
    await showDialog<void>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('Server settings'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ServerSettingsForm(
                  initialValue: _settings.baseUrl?.toString() ?? '',
                  settings: _settings,
                  onSave: _saveServer,
                  onSaved: () => Navigator.of(context).pop(),
                ),
                if (_session?.offline.isSupported == true) ...[
                  const Divider(height: 32),
                  OfflineLibrarySettings(controller: _session!.offline),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff65558f)),
        useMaterial3: true,
      ),
      home: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) {
          if (_settings.isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final session = _session;
          if (!_settings.isConfigured || session == null) {
            return SettingsScreen(settings: _settings, onSave: _saveServer);
          }
          return LibraryScreen(
            key: ValueKey(_settings.baseUrl.toString()),
            library: session.library,
            playback: session.playback,
            api: session.libraryApi,
            offline: session.offline,
            onOpenSettings: () => _showSettings(context),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _replacementGeneration += 1;
    _session?.dispose();
    if (_ownsPlaybackSession) {
      unawaited(_playbackSession.close());
    }
    _settings.dispose();
    super.dispose();
  }
}

final class _ClientSession {
  _ClientSession({
    required this.baseUrl,
    required this.library,
    required this.playback,
    required this.offline,
  });

  final ApiBaseUrl baseUrl;
  final LibraryController library;
  final PlaybackController playback;
  final OfflineLibraryController offline;

  CatalogApi get libraryApi => library.api;

  void dispose() {
    library.dispose();
    offline.dispose();
  }
}
