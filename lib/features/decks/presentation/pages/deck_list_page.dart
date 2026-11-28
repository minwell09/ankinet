import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_theme.dart';
import '../../../../core/config/injection_container.dart';
import '../../../../core/database/local_database.dart';
import '../../../../core/services/tts_cache_service.dart';
import '../../../../core/ui/pixel_widgets.dart';
import '../../../../core/utils/file_export.dart';
import '../../../nlp_extractor/domain/entities/extracted_token.dart';
import '../../../nlp_extractor/domain/usecases/create_cards_from_tokens_usecase.dart';
import '../../../settings/data/services/backup_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../stats/presentation/providers/stats_provider.dart';
import '../../domain/entities/deck.dart';
import '../../domain/usecases/lookup_pronunciation_usecase.dart';
import '../../domain/usecases/manage_cards_and_decks_usecase.dart';
import '../../domain/usecases/manage_leech_cards_usecase.dart';
import '../providers/deck_provider.dart';
import '../widgets/card_edit_dialog.dart';

class DeckListPage extends ConsumerStatefulWidget {
  const DeckListPage({super.key});

  @override
  ConsumerState<DeckListPage> createState() => _DeckListPageState();
}

class _DeckListPageState extends ConsumerState<DeckListPage> {
  bool _isBackingUp = false;
  final TextEditingController _lookupController = TextEditingController();
  DictionaryLookupResult? _lookupResult;
  String? _lookupQuery;
  bool _isLookingUp = false;
  String? _lookupTargetDeckId;
  bool _saveAsLemma = true;
  bool _isWordAlreadySaved = false;
  bool _isSavingLookupCard = false;

  @override
  void dispose() {
    _lookupController.dispose();
    super.dispose();
  }

  String? _effectiveLookupDeckId(List<Deck> decks) {
    if (decks.isEmpty) return null;
    if (_lookupTargetDeckId != null &&
        decks.any((d) => d.id == _lookupTargetDeckId)) {
      return _lookupTargetDeckId;
    }
    return decks.first.id;
  }

  Future<void> _checkLookupDuplicate({
    required DictionaryLookupResult? result,
    required String? deckId,
    required bool saveAsLemma,
  }) async {
    if (result == null || deckId == null) {
      if (mounted) setState(() => _isWordAlreadySaved = false);
      return;
    }
    final targetWord = result.wordToSave(saveAsLemma: saveAsLemma).toLowerCase();
    try {
      final db = await sl<LocalDatabase>().database;
      final rows = await db.query(
        'cards',
        columns: const ['id'],
        where: 'deck_id = ? AND LOWER(word) = ?',
        whereArgs: [deckId, targetWord],
        limit: 1,
      );
      if (mounted) {
        setState(() => _isWordAlreadySaved = rows.isNotEmpty);
      }
    } catch (_) {
      if (mounted) setState(() => _isWordAlreadySaved = false);
    }
  }

  Future<void> _lookupPronunciation(String rawWord) async {
    final word = rawWord.trim().toLowerCase();
    if (word.isEmpty) return;
    setState(() {
      _isLookingUp = true;
      _lookupQuery = word;
      _saveAsLemma = true;
      _isWordAlreadySaved = false;
    });
    final resolved = await sl<LookupPronunciationUseCase>().lookupDual(word);
    if (!mounted) return;
    final decks = ref.read(deckListProvider).valueOrNull ?? const <Deck>[];
    final deckId = _effectiveLookupDeckId(decks);
    setState(() {
      _lookupResult = resolved;
      _lookupTargetDeckId = deckId;
      _isLookingUp = false;
    });
    await _checkLookupDuplicate(
      result: resolved,
      deckId: deckId,
      saveAsLemma: true,
    );
  }

  Future<void> _saveLookupCard(List<Deck> decks) async {
    final result = _lookupResult;
    final deckId = _effectiveLookupDeckId(decks);
    if (result == null || deckId == null || _isWordAlreadySaved) return;

    setState(() => _isSavingLookupCard = true);
    try {
      final targetWord = result.wordToSave(saveAsLemma: _saveAsLemma);
      final ipaUs = result.ipaUsToSave(saveAsLemma: _saveAsLemma);
      final ipaUk = result.ipaUkToSave(saveAsLemma: _saveAsLemma);
      final token = ExtractedToken(
        surfaceWord: targetWord,
        lemma: result.lemmaWord ?? targetWord,
        phonetic: ipaUs.isNotEmpty ? ipaUs : ipaUk,
        phoneticUs: ipaUs,
        phoneticUk: ipaUk,
        translation: result.displayMeaning.isNotEmpty
            ? result.displayMeaning
            : '(${result.displayPos}) $targetWord',
        partOfSpeech: result.displayPos,
        sourceSentence: '',
        radicals: const [],
        isFromOfflineBundle: true,
      );

      final res = await sl<CreateCardsFromTokensUseCase>()(
        deckId: deckId,
        selectedTokens: [token],
      );
      if (!mounted) return;
      res.fold(
        (failure) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi lưu thẻ: ${failure.message}')),
        ),
        (_) {
          setState(() => _isWordAlreadySaved = true);
          ref.read(cardsRevisionProvider.notifier).state++;
          ref.invalidate(deckListProvider);
          ref.invalidate(studyStatsProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã lưu thẻ "$targetWord" vào bộ thẻ!')),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _isSavingLookupCard = false);
    }
  }

  Future<void> _quickBackupJson() async {
    setState(() => _isBackingUp = true);
    try {
      final bytes = await sl<BackupService>().exportFullBackupJsonBytes();
      final path = await saveAndShareBytes(
        fileName: 'VocabAnki_FullBackup_v6.json',
        bytes: bytes,
        mimeType: 'application/json',
      );
      ref.invalidate(studySettingsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã sao lưu JSON thành công ($path)!',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi sao lưu JSON: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _showDeckFormDialog({Deck? existing}) async {
    final px = PixelColors.of(context);
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: PixelCard(
          backgroundColor: px.surface,
          borderColor: px.primary,
          borderWidth: 3,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PixelSectionHeader(
                  title: existing == null ? 'TẠO BỘ THẺ MỚI' : 'SỬA BỘ THẺ',
                  icon: existing == null ? Icons.add_box : Icons.edit,
                  accentColor: px.primary,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên bộ thẻ',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PixelButton(
                      label: 'HỦY',
                      backgroundColor: px.surfaceAlt,
                      foregroundColor: px.ink,
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                    const SizedBox(width: 10),
                    PixelButton(
                      label: 'LƯU',
                      icon: Icons.save_rounded,
                      backgroundColor: px.emerald,
                      onPressed: () {
                        if (nameCtrl.text.trim().isEmpty) return;
                        Navigator.of(ctx).pop(true);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved != true || !mounted) {
      nameCtrl.dispose();
      descCtrl.dispose();
      return;
    }

    if (existing == null) {
      await sl<CreateDeckUseCase>()(
        name: nameCtrl.text.trim(),
        description: descCtrl.text.trim(),
      );
    } else {
      await sl<UpdateDeckUseCase>()(
        deckId: existing.id,
        name: nameCtrl.text.trim(),
        description: descCtrl.text.trim(),
      );
    }

    nameCtrl.dispose();
    descCtrl.dispose();
    ref.invalidate(deckListProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existing == null ? 'Đã tạo bộ thẻ mới!' : 'Đã cập nhật bộ thẻ!',
        ),
      ),
    );
  }

  Future<void> _deleteDeck(Deck deck) async {
    final confirmed = await showPixelDeleteConfirmDialog(
      context,
      title: 'XÓA BỘ THẺ "${deck.name}"?',
      message:
          'Toàn bộ ${deck.totalCards} thẻ và lịch sử ôn tập trong bộ thẻ này sẽ bị xóa vĩnh viễn.',
    );
    if (!confirmed) return;

    final res = await sl<DeleteDeckUseCase>()(deck.id);
    if (!mounted) return;
    res.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi xóa bộ thẻ: ${failure.message}')),
      ),
      (_) {
        ref.invalidate(deckListProvider);
        ref.invalidate(leechCardsProvider);
        ref.invalidate(studyStatsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã xóa bộ thẻ "${deck.name}"!')),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final decksAsync = ref.watch(deckListProvider);
    final leechesAsync = ref.watch(leechCardsProvider);
    final settingsAsync = ref.watch(studySettingsProvider);
    final settings = settingsAsync.valueOrNull;
    final px = PixelColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    final shouldRemindBackup =
        settings?.shouldRemindBackup(isWeb: kIsWeb) ?? kIsWeb;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: px.primary,
                border: Border.all(color: px.shadow, width: 1.5),
              ),
              child: Text(
                '16-BIT',
                style: TextStyle(
                  fontFamily: AppTheme.pixelDisplayFont,
                  fontFamilyFallback: AppTheme.fontFallback,
                  color: px.ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text('VOCABANKI'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _SquareAppBarButton(
              icon: Icons.add_rounded,
              tooltip: 'Tạo bộ thẻ mới',
              onTap: () => _showDeckFormDialog(),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8, right: 12),
            child: _SquareAppBarButton(
              icon: _isBackingUp
                  ? Icons.hourglass_top_rounded
                  : Icons.cloud_upload_outlined,
              tooltip: 'Đồng bộ / Sao lưu JSON',
              onTap: _isBackingUp ? null : _quickBackupJson,
            ),
          ),
        ],
      ),
      body: decksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: PixelCard(
            margin: const EdgeInsets.all(20),
            backgroundColor: colorScheme.errorContainer,
            child: Text('Error: $err'),
          ),
        ),
        data: (decks) {
          final leeches = leechesAsync.valueOrNull ?? const [];

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(deckListProvider);
              ref.invalidate(leechCardsProvider);
              ref.invalidate(studySettingsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
              children: [
                // Compact Pronunciation Search Bar (-45% height)
                PixelCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: TextField(
                                controller: _lookupController,
                                style: const TextStyle(fontSize: 13.5),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  hintText: 'Tra từ Anh-Mỹ / Anh-Anh...',
                                  prefixIcon: Icon(Icons.search, size: 18),
                                  prefixIconConstraints: BoxConstraints(
                                    minWidth: 34,
                                    minHeight: 34,
                                  ),
                                ),
                                textInputAction: TextInputAction.search,
                                onSubmitted: _lookupPronunciation,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          PixelButton(
                            label: 'TRA',
                            icon: Icons.bolt,
                            backgroundColor: px.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 8,
                            ),
                            onPressed: _isLookingUp
                                ? null
                                : () => _lookupPronunciation(
                                      _lookupController.text,
                                    ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Gợi ý:',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: px.inkMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          for (final entry in const [
                            'schedule',
                            'water',
                            'better',
                            'car',
                          ].indexed) ...[
                            if (entry.$1 > 0)
                              Text(
                                '•',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: px.inkMuted.withValues(alpha: 0.6),
                                ),
                              ),
                            InkWell(
                              onTap: () {
                                _lookupController.text = entry.$2;
                                _lookupPronunciation(entry.$2);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 1,
                                ),
                                child: Text(
                                  entry.$2,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: px.primaryBorder,
                                    decoration: TextDecoration.underline,
                                    decorationColor: px.primaryBorder
                                        .withValues(alpha: 0.45),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_isLookingUp) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                      ] else if (_lookupQuery != null) ...[
                        const Divider(height: 16),
                        if (_lookupResult == null)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Không tìm thấy "$_lookupQuery" trong từ điển.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              IconButton(
                                iconSize: 16,
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() {
                                  _lookupQuery = null;
                                  _lookupResult = null;
                                }),
                              ),
                            ],
                          )
                        else ...[
                          // LookupHeaderWithSave: Word + POS + Deck Dropdown + Save 1-Tap Button
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  '${_lookupResult!.queryWord.toUpperCase()} (${_lookupResult!.displayPos})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              IconButton(
                                iconSize: 16,
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Đóng kết quả',
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() {
                                  _lookupQuery = null;
                                  _lookupResult = null;
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (_lookupResult!.ipaUs.isNotEmpty)
                                PixelBadge(
                                  icon: Icons.volume_up_rounded,
                                  label: 'US  ${_lookupResult!.ipaUs}',
                                  backgroundColor: colorScheme.primaryContainer,
                                  onTap: () => sl<TtsCacheService>().speak(
                                    _lookupResult!.queryWord,
                                    accent: 'en-US',
                                  ),
                                ),
                              if (_lookupResult!.ipaUk.isNotEmpty)
                                PixelBadge(
                                  icon: Icons.volume_up_rounded,
                                  label: 'UK  ${_lookupResult!.ipaUk}',
                                  backgroundColor:
                                      colorScheme.secondaryContainer,
                                  onTap: () => sl<TtsCacheService>().speak(
                                    _lookupResult!.queryWord,
                                    accent: 'en-GB',
                                  ),
                                ),
                            ],
                          ),
                          // Inflection link: ↳ Dạng chia của: <lemma> (tap to toggle save lemma vs surface)
                          if (_lookupResult!.isInflectedForm) ...[
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final next = !_saveAsLemma;
                                setState(() => _saveAsLemma = next);
                                await _checkLookupDuplicate(
                                  result: _lookupResult,
                                  deckId: _effectiveLookupDeckId(decks),
                                  saveAsLemma: next,
                                );
                              },
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    Text(
                                      '↳ Dạng chia của: ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: px.inkMuted,
                                      ),
                                    ),
                                    Text(
                                      _lookupResult!.lemmaWord!,
                                      style: TextStyle(
                                        fontFamily: AppTheme.monoFont,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: px.cyan,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _saveAsLemma
                                          ? '(sẽ lưu từ gốc)'
                                          : '(sẽ lưu "${_lookupResult!.queryWord}")',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: px.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (_lookupResult!.displayMeaning.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              _lookupResult!.displayMeaning,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                          if (decks.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 36,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: px.surfaceAlt,
                                      border: Border.all(
                                        color:
                                            px.border.withValues(alpha: 0.55),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        isExpanded: true,
                                        isDense: true,
                                        value: _effectiveLookupDeckId(decks),
                                        items: decks.map((d) {
                                          return DropdownMenuItem<String>(
                                            value: d.id,
                                            child: Text(
                                              d.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) async {
                                          if (val == null) return;
                                          setState(
                                            () => _lookupTargetDeckId = val,
                                          );
                                          await _checkLookupDuplicate(
                                            result: _lookupResult,
                                            deckId: val,
                                            saveAsLemma: _saveAsLemma,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PixelButton(
                                  label: _isWordAlreadySaved
                                      ? 'ĐÃ LƯU'
                                      : (_isSavingLookupCard
                                          ? 'ĐANG LƯU...'
                                          : 'LƯU THẺ'),
                                  icon: _isWordAlreadySaved
                                      ? Icons.check_rounded
                                      : Icons.add_rounded,
                                  backgroundColor: _isWordAlreadySaved
                                      ? px.emerald
                                      : px.primary,
                                  foregroundColor: _isWordAlreadySaved
                                      ? Colors.white
                                      : px.ink,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  onPressed:
                                      _isWordAlreadySaved || _isSavingLookupCard
                                          ? null
                                          : () => _saveLookupCard(decks),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ],
                    ],
                  ),
                ),

                // Compact Backup Reminder Banner
                if (shouldRemindBackup)
                  PixelCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    backgroundColor: const Color(0xFFE7F0DA),
                    child: Row(
                      children: [
                        Icon(Icons.save_alt_rounded,
                            color: px.emerald, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            settings?.lastBackupEpochMs == null
                                ? 'Chưa có bản sao lưu JSON. Nhấn ☁ để bảo vệ tiến độ học.'
                                : 'Đã quá ${settings!.backupReminderDays} ngày kể từ lần sao lưu gần nhất.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: px.ink,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _isBackingUp ? null : _quickBackupJson,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(_isBackingUp ? '...' : 'Sao lưu'),
                        ),
                      ],
                    ),
                  ),

                // Deck Quest Cards (Full-width title, unified 4-col stat bar, full-width primary CTA)
                ...decks.map((deck) {
                  final mastered = (deck.totalCards - deck.newCards)
                      .clamp(0, deck.totalCards);
                  final masteryRatio =
                      deck.totalCards > 0 ? mastered / deck.totalCards : 0.0;
                  final isExtraNew =
                      deck.dueCards == 0 && deck.totalNewCards > 0;
                  final primaryLabel = deck.dueCards > 0
                      ? 'ÔN TẬP NGAY (${deck.dueCards})'
                      : (isExtraNew
                          ? 'HỌC THÊM (${deck.totalNewCards})'
                          : 'ÔN TẬP NGAY (0)');

                  return PixelCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Full-width Deck Title (never squeezed or broken)
                        Text(
                          deck.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontSize: 18),
                        ),
                        if (deck.description.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            deck.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 10),
                        PixelProgressBar(
                          progress: masteryRatio,
                          fillColor: px.emerald,
                          height: 12,
                        ),
                        const SizedBox(height: 10),
                        // Unified 4-column Stat Bar (no outer border, 1px vertical dividers)
                        PixelStatBar(
                          items: [
                            (
                              label: 'Tổng',
                              value: '${deck.totalCards}',
                              valueColor: px.ink,
                            ),
                            (
                              label: 'Mới',
                              value: deck.totalNewCards > deck.newCards
                                  ? '${deck.newCards}/${deck.totalNewCards}'
                                  : '${deck.totalNewCards}',
                              valueColor: px.primaryBorder,
                            ),
                            (
                              label: 'Học',
                              value: '${deck.learningCards}',
                              valueColor: px.emerald,
                            ),
                            (
                              label: 'Đến hạn',
                              value: '${deck.reviewDueCards}',
                              valueColor: px.cyan,
                            ),
                          ],
                        ),
                        if (deck.leechCards > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            '⚠ ${deck.leechCards} thẻ Leech cần xem lại',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: px.coral,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        // Full-width Primary CTA
                        PixelButton(
                          expand: true,
                          label: primaryLabel,
                          icon: Icons.play_arrow_rounded,
                          backgroundColor:
                              isExtraNew ? px.primary : px.emerald,
                          foregroundColor:
                              isExtraNew ? px.ink : Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          onPressed: () => context.go(
                            isExtraNew
                                ? '/decks/study/${deck.id}?extraNew=1'
                                : '/decks/study/${deck.id}',
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Compact Footer Secondary Actions
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () =>
                                  context.go('/decks/cards/${deck.id}'),
                              icon: Icon(
                                Icons.style_outlined,
                                size: 16,
                                color: px.inkMuted,
                              ),
                              label: Text(
                                'Quản lý thẻ (${deck.totalCards})',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: px.inkMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Sửa bộ thẻ',
                              icon: Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: px.inkMuted,
                              ),
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  _showDeckFormDialog(existing: deck),
                            ),
                            IconButton(
                              tooltip: 'Xóa bộ thẻ',
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: px.coral,
                              ),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _deleteDeck(deck),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),

                // Leech Cards Manager
                if (leeches.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  PixelSectionHeader(
                    title: 'THẺ LEECH (HAY QUÊN)',
                    icon: Icons.warning_amber_rounded,
                    accentColor: px.coral,
                  ),
                  const SizedBox(height: 10),
                  ...leeches.map((card) {
                    return PixelCard(
                      margin: const EdgeInsets.only(bottom: 10),
                      backgroundColor: colorScheme.errorContainer,
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${card.word} (${card.formattedPhoneticSummary}) • ${card.lapses} lần quên',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(card.translation),
                                if (card.effectiveClozeSentence.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Cloze: "${card.effectiveClozeSentence}"',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: card.isSuspended
                                ? 'Mở khóa thẻ'
                                : 'Tạm ẩn thẻ',
                            icon: Icon(
                              card.isSuspended
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () async {
                              await sl<ToggleSuspendCardUseCase>()(
                                card.id,
                                suspended: !card.isSuspended,
                              );
                              ref.invalidate(deckListProvider);
                              ref.invalidate(leechCardsProvider);
                            },
                          ),
                          IconButton(
                            tooltip: 'Đặt lại tiến độ (Reset Leech)',
                            icon: const Icon(Icons.restart_alt),
                            onPressed: () async {
                              await sl<ResetLeechCardUseCase>()(card.id);
                              ref.invalidate(deckListProvider);
                              ref.invalidate(leechCardsProvider);
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SquareAppBarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _SquareAppBarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF5E3D26),
            border: Border.all(
              color: px.woodHighlight.withValues(alpha: 0.45),
              width: 1.5,
            ),
          ),
          child: Icon(icon, size: 19, color: px.inkOnWood),
        ),
      ),
    );
  }
}
