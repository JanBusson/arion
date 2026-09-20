import 'package:flutter/foundation.dart';

import 'api_base_url.dart';
import 'settings_store.dart';

final class SettingsController extends ChangeNotifier {
  SettingsController(
    this._store, {
    this.seedBaseUrl = const String.fromEnvironment('ARION_API_BASE_URL'),
  });

  final SettingsStore _store;
  final String seedBaseUrl;

  ApiBaseUrl? _baseUrl;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  ApiBaseUrl? get baseUrl => _baseUrl;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;
  bool get isConfigured => _baseUrl != null;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _store.readBaseUrl();
      final candidate = saved?.trim().isNotEmpty == true ? saved! : seedBaseUrl;
      if (candidate.trim().isNotEmpty) {
        _baseUrl = ApiBaseUrl.parse(candidate);
      }
    } on FormatException {
      _baseUrl = null;
      _error = 'The saved server address is invalid. Enter it again.';
    } on Object {
      _error = 'The saved server setting could not be loaded.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> save(String value) async {
    ApiBaseUrl parsed;
    try {
      parsed = ApiBaseUrl.parse(value);
    } on FormatException catch (error) {
      _error = error.message.toString();
      notifyListeners();
      return false;
    }

    _isSaving = true;
    _error = null;
    notifyListeners();
    try {
      await _store.writeBaseUrl(parsed.toString());
      _baseUrl = parsed;
      return true;
    } on Object {
      _error = 'The server setting could not be saved.';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
