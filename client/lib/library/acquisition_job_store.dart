abstract interface class AcquisitionJobStore {
  Future<String?> readActiveJobId();
  Future<void> writeActiveJobId(String jobId);
  Future<void> clearActiveJobId();
}

final class MemoryAcquisitionJobStore implements AcquisitionJobStore {
  String? value;

  @override
  Future<String?> readActiveJobId() async => value;

  @override
  Future<void> writeActiveJobId(String jobId) async => value = jobId;

  @override
  Future<void> clearActiveJobId() async => value = null;
}
