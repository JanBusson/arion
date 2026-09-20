import 'package:shared_preferences/shared_preferences.dart';

import 'settings_store.dart';

final class SharedPreferencesSettingsStore implements SettingsStore {
  SharedPreferencesSettingsStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _baseUrlKey = 'arion.apiBaseUrl';

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> readBaseUrl() => _preferences.getString(_baseUrlKey);

  @override
  Future<void> writeBaseUrl(String value) async {
    await _preferences.setString(_baseUrlKey, value);
  }
}
