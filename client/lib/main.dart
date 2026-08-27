import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'configuration/shared_preferences_settings_store.dart';
import 'library/catalog_api.dart';
import 'library/shared_preferences_acquisition_job_store.dart';
import 'playback/just_audio_adapter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ArionApp(
      settingsStore: SharedPreferencesSettingsStore(),
      catalogApiFactory: (baseUrl) =>
          ArionApi(baseUrl: baseUrl, client: http.Client()),
      audioPlayerFactory: JustAudioAdapter.new,
      acquisitionJobStore: SharedPreferencesAcquisitionJobStore(),
    ),
  );
}
