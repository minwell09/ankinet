class TtsFileStore {
  bool get isSupported => false;

  Future<void> init() async {}

  Future<String?> getExistingFilePath(String fileName) async => null;

  Future<String?> getTargetFilePathIfMissing(String fileName) async => null;

  Future<int> getCachedFileCount() async => 0;

  Future<void> clearCache() async {}
}
