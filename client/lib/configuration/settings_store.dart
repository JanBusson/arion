abstract interface class SettingsStore {
  Future<String?> readBaseUrl();

  Future<void> writeBaseUrl(String value);
}
