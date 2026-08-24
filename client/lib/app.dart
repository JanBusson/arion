import 'package:flutter/material.dart';

import 'configuration/api_base_url.dart';
import 'configuration/settings_controller.dart';
import 'configuration/settings_store.dart';
import 'library/catalog_api.dart';
import 'library/library_controller.dart';
import 'playback/audio_player_port.dart';
import 'playback/playback_controller.dart';
import 'ui/library_screen.dart';
import 'ui/settings_screen.dart';

typedef CatalogApiFactory = CatalogApi Function(ApiBaseUrl baseUrl);
typedef AudioPlayerFactory = AudioPlayerPort Function();

final class ArionApp extends StatefulWidget {
  const ArionApp({
    required this.settingsStore,
    required this.catalogApiFactory,
    required this.audioPlayerFactory,
    this.seedBaseUrl = const String.fromEnvironment('ARION_API_BASE_URL'),
    super.key,
  });

  final SettingsStore settingsStore;
  final CatalogApiFactory catalogApiFactory;
  final AudioPlayerFactory audioPlayerFactory;
  final String seedBaseUrl;

  @override
  State<ArionApp> createState() => _ArionAppState();
}

final class _ArionAppState extends State<ArionApp> {
  late final SettingsController _settings;
  _ClientSession? _session;

  @override
  void initState() {
    super.initState();
    _settings = SettingsController(
      widget.settingsStore,
      seedBaseUrl: widget.seedBaseUrl,
    );
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _settings.load();
    if (!mounted) {
      return;
    }
    _replaceSession(_settings.baseUrl);
  }

  Future<bool> _saveServer(String value) async {
    final saved = await _settings.save(value);
    if (saved && mounted) {
      _replaceSession(_settings.baseUrl);
    }
    return saved;
  }

  void _replaceSession(ApiBaseUrl? baseUrl) {
    final oldSession = _session;
    setState(() {
      _session = baseUrl == null
          ? null
          : _ClientSession(
              library: LibraryController(widget.catalogApiFactory(baseUrl)),
              playback: PlaybackController(widget.audioPlayerFactory()),
            );
    });
    oldSession?.dispose();
  }

  Future<void> _showSettings(BuildContext dialogContext) async {
    await showDialog<void>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('Server settings'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ServerSettingsForm(
            initialValue: _settings.baseUrl?.toString() ?? '',
            settings: _settings,
            onSave: _saveServer,
            onSaved: () => Navigator.of(context).pop(),
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
            onOpenSettings: () => _showSettings(context),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _session?.dispose();
    _settings.dispose();
    super.dispose();
  }
}

final class _ClientSession {
  _ClientSession({required this.library, required this.playback});

  final LibraryController library;
  final PlaybackController playback;

  CatalogApi get libraryApi => library.api;

  void dispose() {
    library.dispose();
    playback.dispose();
  }
}
