import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_theme.dart';
import '../../../../core/config/injection_container.dart';
import '../../../../core/database/offline_dictionary_database.dart';
import '../../../../core/services/tts_cache_service.dart';
import '../../../../core/ui/pixel_widgets.dart';
import '../../../../core/utils/file_export.dart';
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
  OfflineDictEntry? _lookupEntry;
  String? _lookupQuery;
  bool _isLookingUp = false;

  @override
  void dispose() {
    _lookupController.dispose();
    super.dispose();
  }

  Future<void> _lookupPronunciation(String rawWord) async {
    final word = rawWord.trim().toLowerCase();
    if (word.isEmpty) return;
    setState(() {
      _isLookingUp = true;
      _lookupQuery = word;
    });
    final entry = await sl<LookupPronunciationUseCase>()(word);
    if (!mounted) return;
    setState(() {
      _lookupEntry = entry;
      _isLookingUp = false;
    });
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
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: px.primary,
                border: Border.all(color: px.border, width: 2),
              ),
              child: Text(
                '16-BIT',
                style: TextStyle(
                  fontFamily: AppTheme.pixelDisplayFont,
                  color: px.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'VOCABANKI • FSRS-4.5',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (settings != null && settings.hasCustomFsrsWeights) ...[
              const SizedBox(width: 8),
              PixelBadge(
                label: '17-WEIGHT',
                backgroundColor: px.primary,
                foregroundColor: px.ink,
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Tạo bộ thẻ mới',
            icon: const Icon(Icons.add_box_outlined),
            onPressed: () => _showDeckFormDialog(),
          ),
          IconButton(
            tooltip: 'Sao lưu nhanh JSON',
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: _isBackingUp ? null : _quickBackupJson,
          ),
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(deckListProvider);
              ref.invalidate(leechCardsProvider);
              ref.invalidate(studySettingsProvider);
            },
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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Pixel Pronunciation Scanner (SQLite OpenDictData US/UK IPA)
              PixelCard(
                woodFrame: true,
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PixelSectionHeader(
                      title: 'TRA PHÁT ÂM ANH-MỸ (US) & ANH-ANH (UK)',
                      icon: Icons.record_voice_over_rounded,
                      accentColor: px.cyan,
                      trailing: const PixelBadge(label: 'SQLite 205K'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _lookupController,
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Nhập từ (vd: schedule, water, car)...',
                              prefixIcon: Icon(Icons.search, size: 20),
                            ),
                            textInputAction: TextInputAction.search,
                            onSubmitted: _lookupPronunciation,
                          ),
                        ),
                        const SizedBox(width: 10),
                        PixelButton(
                          label: 'TRA',
                          icon: Icons.bolt,
                          backgroundColor: px.primary,
                          onPressed: _isLookingUp
                              ? null
                              : () =>
                                  _lookupPronunciation(_lookupController.text),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: const ['schedule', 'water', 'better', 'car']
                          .map((sample) {
                        return PixelBadge(
                          label: sample,
                          backgroundColor: px.surfaceAlt,
                          onTap: () {
                            _lookupController.text = sample;
                            _lookupPronunciation(sample);
                          },
                        );
                      }).toList(),
                    ),
                    if (_isLookingUp) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ] else if (_lookupQuery != null) ...[
                      const Divider(height: 22),
                      if (_lookupEntry == null)
                        Text(
                          'Không tìm thấy "$_lookupQuery" trong từ điển SQLite.',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else ...[
                        Text(
                          '${_lookupEntry!.word.toUpperCase()} (${_lookupEntry!.pos})',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_lookupEntry!.ipaUs.isNotEmpty)
                              PixelBadge(
                                icon: Icons.volume_up_rounded,
                                label: 'US  ${_lookupEntry!.ipaUs}',
                                backgroundColor: colorScheme.primaryContainer,
                                onTap: () => sl<TtsCacheService>().speak(
                                  _lookupEntry!.word,
                                  accent: 'en-US',
                                ),
                              ),
                            if (_lookupEntry!.ipaUk.isNotEmpty)
                              PixelBadge(
                                icon: Icons.volume_up_rounded,
                                label: 'UK  ${_lookupEntry!.ipaUk}',
                                backgroundColor: colorScheme.secondaryContainer,
                                onTap: () => sl<TtsCacheService>().speak(
                                  _lookupEntry!.word,
                                  accent: 'en-GB',
                                ),
                              ),
                          ],
                        ),
                        if (_lookupEntry!.vi.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _lookupEntry!.vi,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ],
                    ],
                  ],
                ),
              ),

              // Pixel Backup Reminder Banner
              if (shouldRemindBackup)
                PixelCard(
                  margin: const EdgeInsets.only(bottom: 16),
                  backgroundColor: colorScheme.tertiaryContainer,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PixelSectionHeader(
                        title: kIsWeb
                            ? 'LƯU Ý BẢN WEB • SAO LƯU INDEXEDDB'
                            : 'NHẮC SAO LƯU DỮ LIỆU FSRS',
                        icon: Icons.save_alt_rounded,
                        accentColor: px.gold,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        settings?.lastBackupEpochMs == null
                            ? 'Bạn chưa xuất bản sao lưu JSON nào. Hãy sao lưu định kỳ để bảo vệ tiến độ thẻ & lịch sử revlog.'
                            : 'Đã quá ${settings!.backupReminderDays} ngày kể từ lần sao lưu gần nhất.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          PixelButton(
                            label: _isBackingUp
                                ? 'ĐANG XUẤT...'
                                : 'SAO LƯU JSON NGAY',
                            icon: Icons.download_rounded,
                            backgroundColor: px.emerald,
                            onPressed: _isBackingUp ? null : _quickBackupJson,
                          ),
                          PixelButton(
                            label: 'CÀI ĐẶT',
                            icon: Icons.tune,
                            backgroundColor: px.surface,
                            foregroundColor: px.ink,
                            onPressed: () => context.go('/settings'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              // Deck Quest Cards
              ...decks.map((deck) {
                final mastered = (deck.totalCards - deck.newCards)
                    .clamp(0, deck.totalCards);
                final masteryRatio =
                    deck.totalCards > 0 ? mastered / deck.totalCards : 0.0;

                return PixelCard(
                  woodFrame: true,
                  showRivets: true,
                  backgroundColor: px.cardParchment,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  deck.name,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  deck.description,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: px.inkMuted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          PixelButton(
                            label: 'ÔN TẬP (${deck.dueCards})',
                            icon: Icons.play_arrow_rounded,
                            backgroundColor: px.emerald,
                            onPressed: () =>
                                context.go('/decks/study/${deck.id}'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      PixelProgressBar(
                        progress: masteryRatio,
                        fillColor: px.primary,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          PixelBadge(
                            label: 'TỔNG: ${deck.totalCards}',
                            backgroundColor: px.surfaceAlt,
                          ),
                          PixelBadge(
                            label: 'MỚI: ${deck.newCards}',
                            backgroundColor: colorScheme.primaryContainer,
                          ),
                          PixelBadge(
                            label: 'ĐANG HỌC: ${deck.learningCards}',
                            backgroundColor: colorScheme.tertiaryContainer,
                          ),
                          PixelBadge(
                            label: 'ĐẾN HẠN: ${deck.reviewDueCards}',
                            backgroundColor: colorScheme.secondaryContainer,
                          ),
                          if (deck.leechCards > 0)
                            PixelBadge(
                              label: 'LEECH: ${deck.leechCards}',
                              backgroundColor: colorScheme.errorContainer,
                            ),
                        ],
                      ),
                      const Divider(height: 20),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          PixelButton(
                            label: 'QUẢN LÝ THẺ (${deck.totalCards})',
                            icon: Icons.edit_note_rounded,
                            backgroundColor: px.surfaceAlt,
                            foregroundColor: px.ink,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            onPressed: () =>
                                context.go('/decks/cards/${deck.id}'),
                          ),
                          PixelButton(
                            label: 'SỬA BỘ THẺ',
                            icon: Icons.edit_rounded,
                            backgroundColor: px.surfaceAlt,
                            foregroundColor: px.ink,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            onPressed: () =>
                                _showDeckFormDialog(existing: deck),
                          ),
                          PixelButton(
                            label: 'XÓA',
                            icon: Icons.delete_outline_rounded,
                            backgroundColor: px.coral,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
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
                const SizedBox(height: 4),
                PixelSectionHeader(
                  title: 'THẺ LEECH (HAY QUÊN)',
                  icon: Icons.warning_amber_rounded,
                  accentColor: px.coral,
                ),
                const SizedBox(height: 10),
                ...leeches.map((card) {
                  return PixelCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    backgroundColor: colorScheme.errorContainer,
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
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(card.translation),
                              if (card.effectiveClozeSentence.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Cloze: "${card.effectiveClozeSentence}"',
                                  style: Theme.of(context).textTheme.bodySmall,
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
          );
        },
      ),
    );
  }
}
