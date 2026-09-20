import 'package:shared_preferences/shared_preferences.dart';

import 'acquisition_job_store.dart';

final class SharedPreferencesAcquisitionJobStore
    implements AcquisitionJobStore {
  SharedPreferencesAcquisitionJobStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _jobIdKey = 'arion.activeAcquisitionJobId';
  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> readActiveJobId() => _preferences.getString(_jobIdKey);

  @override
  Future<void> writeActiveJobId(String jobId) =>
      _preferences.setString(_jobIdKey, jobId);

  @override
  Future<void> clearActiveJobId() => _preferences.remove(_jobIdKey);
}
