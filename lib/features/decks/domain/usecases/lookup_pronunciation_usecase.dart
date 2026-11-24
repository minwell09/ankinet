import '../../../../core/database/offline_dictionary_database.dart';

class LookupPronunciationUseCase {
  final OfflineDictionaryDatabase dictionaryDatabase;

  const LookupPronunciationUseCase(this.dictionaryDatabase);

  Future<OfflineDictEntry?> call(String rawWord) async {
    final word = rawWord.trim().toLowerCase();
    if (word.isEmpty) return null;
    final res = await dictionaryDatabase.lookupBatch([word]);
    return res[word];
  }
}
