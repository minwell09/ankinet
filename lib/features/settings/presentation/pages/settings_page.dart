import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_theme.dart';
import '../../../../core/config/injection_container.dart';
import '../../../../core/database/local_database.dart';
import '../../../../core/database/offline_dictionary_database.dart';
import '../../../../core/services/tts_cache_service.dart';
import '../../../../core/settings/study_settings.dart';
import '../../../../core/srs/fsrs_weight_optimizer.dart';
import '../../../../core/ui/pixel_widgets.dart';
import '../../../../core/utils/file_export.dart';
import '../../../decks/presentation/providers/deck_provider.dart';
import '../../../stats/presentation/providers/stats_provider.dart';
import '../../data/services/backup_service.dart';
import '../providers/settings_provider.dart';

final offlineDictMetaProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
  return sl<OfflineDictionaryDatabase>().getMetadata();
});

final revlogCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final db = await sl<LocalDatabase>().database;
  final rows = await db.rawQuery('SELECT COUNT(*) AS cnt FROM revlog');
  return (rows.first['cnt'] as int?) ?? 0;
});

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _isBusy = false;
  bool _isOptimizingFsrs = false;
  bool _showDictDetails = false;
  bool _showFsrsWeights = false;
  FsrsOptimizationResult? _lastOptResult;
  final TextEditingController _geminiKeyCtrl = TextEditingController();
  bool _geminiKeyInitialized = false;

  @override
  void dispose() {
    _geminiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _exportAnkiApkg() async {
    setState(() => _isBusy = true);
    try {
      final bytes = await sl<BackupService>().exportAnkiApkgBytes();
      final path = await saveAndShareBytes(
        fileName: 'VocabAnki_FSRS_Export.apkg',
        bytes: bytes,
        mimeType: 'application/octet-stream',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã xuất Anki Package (.apkg): $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi xuất .apkg: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _exportAnkiCsv() async {
    setState(() => _isBusy = true);
    try {
      final bytes = await sl<BackupService>().exportAnkiCsvBytes();
      final path = await saveAndShareBytes(
        fileName: 'VocabAnki_Cards.tsv',
        bytes: bytes,
        mimeType: 'text/tab-separated-values',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã xuất file Anki CSV/TSV: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi xuất CSV: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _exportBackupJson() async {
    setState(() => _isBusy = true);
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
            'Đã sao lưu toàn bộ dữ liệu (JSON): $path. Hãy lưu file này lên Google Drive để an toàn!',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi sao lưu: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['apkg', 'csv', 'tsv', 'txt', 'json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null) return;

    setState(() => _isBusy = true);
    try {
      final name = picked.name.toLowerCase();
      final backup = sl<BackupService>();
      late final int count;
      if (name.endsWith('.apkg')) {
        count = await backup.importAnkiApkgBytes(bytes);
      } else if (name.endsWith('.json')) {
        count = await backup.importFullBackupJsonBytes(bytes);
      } else {
        count = await backup.importAnkiCsvBytes(bytes);
      }

      ref.read(cardsRevisionProvider.notifier).state++;
      ref.invalidate(deckListProvider);
      ref.invalidate(studyStatsProvider);
      ref.invalidate(studySettingsProvider);
      ref.invalidate(revlogCountProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã nhập thành công $count thẻ từ "${picked.name}"!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi nhập file: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _runFsrsOptimization(StudySettings settings) async {
    setState(() => _isOptimizingFsrs = true);
    try {
      final db = await sl<LocalDatabase>().database;
      final rows = await db.query(
        'revlog',
        columns: const ['card_id', 'grade', 'state_before', 'reviewed_at'],
        orderBy: 'card_id ASC, reviewed_at ASC',
      );

      final result = await sl<FsrsWeightOptimizer>().optimizeFromRevlog(
        rows,
        startingWeights: settings.effectiveFsrsWeights,
      );

      setState(() => _lastOptResult = result);

      if (result.usableTransitions > 0) {
        await ref.read(studySettingsProvider.notifier).updateSettings(
              settings.copyWith(customFsrsWeights: result.optimizedWeights),
            );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.usableTransitions > 0
                ? 'Đã tối ưu 17 trọng số FSRS từ ${result.totalReviews} lượt ôn (Log-Loss: ${result.initialLogLoss.toStringAsFixed(4)} ➔ ${result.optimizedLogLoss.toStringAsFixed(4)})!'
                : 'Cần ít nhất các thẻ được ôn từ 2 lần trở lên trong revlog để huấn luyện trọng số.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi tối ưu trọng số FSRS: $e')),
      );
    } finally {
      if (mounted) setState(() => _isOptimizingFsrs = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(studySettingsProvider);
    final dictMetaAsync = ref.watch(offlineDictMetaProvider);
    final revlogCountAsync = ref.watch(revlogCountProvider);
    final notifier = ref.read(studySettingsProvider.notifier);
    final ttsService = sl<TtsCacheService>();
    final px = PixelColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('CÀI ĐẶT'),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (settings) {
          if (!_geminiKeyInitialized) {
            _geminiKeyCtrl.text = settings.geminiApiKey;
            _geminiKeyInitialized = true;
          }

          final dictMeta = dictMetaAsync.valueOrNull ?? const {};
          final totalEntries = dictMeta['total_entries'] ?? '205,066';
          final revlogCount = revlogCountAsync.valueOrNull ?? 0;
          final progressTo1000 =
              (revlogCount / FsrsWeightOptimizer.recommendedMinReviews)
                  .clamp(0.0, 1.0);

          final lastBackupText = settings.lastBackupEpochMs != null
              ? DateTime.fromMillisecondsSinceEpoch(settings.lastBackupEpochMs!)
                  .toLocal()
                  .toString()
                  .substring(0, 16)
              : 'Chưa từng sao lưu';

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            children: [
              // 1. Study Parameters & Daily Limits FIRST (most frequently used)
              PixelCard(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PixelSectionHeader(
                      title: 'THAM SỐ HỌC & GIỚI HẠN HÀNG NGÀY',
                      icon: Icons.tune_rounded,
                      accentColor: px.primary,
                    ),
                    const SizedBox(height: 12),
                    _SliderRow(
                      label: 'Thẻ mới mỗi ngày',
                      valueText: '${settings.newCardsPerDay} thẻ',
                      value: settings.newCardsPerDay.toDouble(),
                      min: 5,
                      max: 100,
                      divisions: 19,
                      onChanged: (v) => notifier.updateSettings(
                        settings.copyWith(newCardsPerDay: v.round()),
                      ),
                    ),
                    _SliderRow(
                      label: 'Lượt ôn tối đa mỗi ngày',
                      valueText: '${settings.maxReviewsPerDay} lượt',
                      value: settings.maxReviewsPerDay.toDouble(),
                      min: 20,
                      max: 500,
                      divisions: 24,
                      onChanged: (v) => notifier.updateSettings(
                        settings.copyWith(maxReviewsPerDay: v.round()),
                      ),
                    ),
                    _SliderRow(
                      label: 'Mục tiêu tỉ lệ nhớ (Retention)',
                      valueText:
                          '${(settings.desiredRetention * 100).round()}%',
                      value: settings.desiredRetention,
                      min: 0.80,
                      max: 0.96,
                      divisions: 16,
                      onChanged: (v) => notifier.updateSettings(
                        settings.copyWith(desiredRetention: v),
                      ),
                    ),
                    _SliderRow(
                      label: 'Ngưỡng thẻ Leech (số lần quên)',
                      valueText: '${settings.leechThreshold} lần',
                      value: settings.leechThreshold.toDouble(),
                      min: 3,
                      max: 12,
                      divisions: 9,
                      onChanged: (v) => notifier.updateSettings(
                        settings.copyWith(leechThreshold: v.round()),
                      ),
                    ),
                    const Divider(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Tự động tạm ẩn thẻ Leech',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Tạm ẩn thẻ khi số lần quên vượt ngưỡng đã đặt.',
                      ),
                      value: settings.suspendLeeches,
                      onChanged: (v) => notifier.updateSettings(
                        settings.copyWith(suspendLeeches: v),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Hiện câu điền khuyết (Cloze) mặt trước',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Tự động che đúng dạng từ xuất hiện trong câu ngữ cảnh.',
                      ),
                      value: settings.showClozeContext,
                      onChanged: (v) => notifier.updateSettings(
                        settings.copyWith(showClozeContext: v),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Offline Dictionary & AI Contextual Translation (collapsed details)
              PixelCard(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PixelSectionHeader(
                      title: 'TỪ ĐIỂN OFFLINE & AI DỊCH NGỮ CẢNH',
                      icon: Icons.menu_book_rounded,
                      accentColor: px.cyan,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          color: px.emerald,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$totalEntries từ • Sẵn sàng',
                            style: TextStyle(
                              fontFamily: AppTheme.monoFont,
                              fontFamilyFallback: AppTheme.fontFallback,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: px.ink,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(
                            () => _showDictDetails = !_showDictDetails,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Text(
                              _showDictDetails
                                  ? 'Ẩn chi tiết ▴'
                                  : 'Chi tiết dữ liệu ▾',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: px.primaryBorder,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_showDictDetails) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        color: px.surfaceAlt,
                        child: Text(
                          '• Tổng mục từ Tiếng Anh: $totalEntries\n'
                          '• Định nghĩa EN → VI: ${dictMeta['vi_entries'] ?? '104,717'} mục\n'
                          '• Phiên âm IPA (Wiktionary + CMUdict): ${dictMeta['ipa_entries'] ?? totalEntries} mục\n'
                          '• Bất quy tắc WordNet: ${dictMeta['irregular_lemmas'] ?? '5,519'} cặp\n'
                          '• Giấy phép: ${dictMeta['license'] ?? 'CC BY-SA 4.0 (Wiktionary) + CMUdict BSD + WordNet 3.0'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _geminiKeyCtrl,
                            obscureText: true,
                            style: const TextStyle(fontSize: 13.5),
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Gemini API Key (Tùy chọn)',
                              hintText: 'Để trống dùng Google Translate',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PixelButton(
                          label: 'LƯU KEY',
                          backgroundColor: px.primary,
                          foregroundColor: px.ink,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          onPressed: () async {
                            await notifier.updateSettings(
                              settings.copyWith(
                                geminiApiKey: _geminiKeyCtrl.text.trim(),
                              ),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Đã lưu cấu hình Gemini API Key!',
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 3. FSRS-4.5 Personal Optimizer (Full-width title, hidden w[0..16])
              PixelCard(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PixelSectionHeader(
                      title: 'TỐI ƯU FSRS-4.5 CÁ NHÂN',
                      icon: Icons.auto_graph_rounded,
                      accentColor: px.emerald,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$revlogCount / ${FsrsWeightOptimizer.recommendedMinReviews} lượt ôn',
                            style: TextStyle(
                              fontFamily: AppTheme.monoFont,
                              fontFamilyFallback: AppTheme.fontFallback,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: px.ink,
                            ),
                          ),
                        ),
                        PixelBadge(
                          label: settings.hasCustomFsrsWeights
                              ? 'CÁ NHÂN'
                              : 'MẶC ĐỊNH',
                          backgroundColor: settings.hasCustomFsrsWeights
                              ? colorScheme.tertiaryContainer
                              : px.surfaceAlt,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    PixelProgressBar(
                      progress: progressTo1000,
                      fillColor: px.emerald,
                      height: 12,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      revlogCount >= FsrsWeightOptimizer.recommendedMinReviews
                          ? 'Đã đủ dữ liệu lịch sử ôn để tối ưu đường cong quên cá nhân.'
                          : 'Khuyến nghị ~1,000 lượt ôn để khớp chính xác nhất (vẫn có thể chạy thử sớm).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_lastOptResult != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Kết quả gần nhất: ${_lastOptResult!.usableTransitions} chuyển đổi • '
                        'Log-Loss ${_lastOptResult!.initialLogLoss.toStringAsFixed(4)} → ${_lastOptResult!.optimizedLogLoss.toStringAsFixed(4)} '
                        '(${_lastOptResult!.improvementPercent.toStringAsFixed(1)}%)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: px.emerald,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    PixelButton(
                      expand: true,
                      backgroundColor: px.primary,
                      foregroundColor: px.ink,
                      icon: Icons.auto_graph_rounded,
                      label: _isOptimizingFsrs
                          ? 'ĐANG TỐI ƯU...'
                          : 'TỐI ƯU TRỌNG SỐ FSRS',
                      onPressed: _isOptimizingFsrs
                          ? null
                          : () => _runFsrsOptimization(settings),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          onTap: () => setState(
                            () => _showFsrsWeights = !_showFsrsWeights,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              _showFsrsWeights
                                  ? 'Ẩn tham số nâng cao ▴'
                                  : 'Xem tham số nâng cao ▾',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: px.primaryBorder,
                              ),
                            ),
                          ),
                        ),
                        if (settings.hasCustomFsrsWeights)
                          TextButton.icon(
                            onPressed: () async {
                              await notifier.updateSettings(
                                settings.copyWith(
                                  clearCustomFsrsWeights: true,
                                ),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Đã khôi phục trọng số FSRS mặc định!',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.restore, size: 16),
                            label: const Text('Khôi phục mặc định'),
                          ),
                      ],
                    ),
                    if (_showFsrsWeights) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        color: px.surfaceAlt,
                        child: SelectableText(
                          'w[0..16]: [${settings.effectiveFsrsWeights.map((w) => w.toStringAsFixed(4)).join(', ')}]',
                          style: TextStyle(
                            fontFamily: AppTheme.monoFont,
                            fontFamilyFallback: AppTheme.fontFallback,
                            fontSize: 11.5,
                            color: px.ink,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 4. Backup & Import/Export Anki
              PixelCard(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PixelSectionHeader(
                      title: 'SAO LƯU & IMPORT / EXPORT',
                      icon: Icons.inventory_2_outlined,
                      accentColor: px.gold,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sao lưu gần nhất: $lastBackupText',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    _SliderRow(
                      label: 'Chu kỳ nhắc sao lưu JSON',
                      valueText: '${settings.backupReminderDays} ngày',
                      value: settings.backupReminderDays.toDouble(),
                      min: 1,
                      max: 14,
                      divisions: 13,
                      onChanged: (v) => notifier.updateSettings(
                        settings.copyWith(backupReminderDays: v.round()),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        PixelButton(
                          label: 'SAO LƯU JSON',
                          icon: Icons.save_alt,
                          backgroundColor: px.emerald,
                          foregroundColor: Colors.white,
                          onPressed: _isBusy ? null : _exportBackupJson,
                        ),
                        PixelButton(
                          label: 'XUẤT .APKG',
                          icon: Icons.archive_outlined,
                          backgroundColor: px.surfaceAlt,
                          foregroundColor: px.ink,
                          onPressed: _isBusy ? null : _exportAnkiApkg,
                        ),
                        PixelButton(
                          label: 'XUẤT CSV',
                          icon: Icons.table_chart_outlined,
                          backgroundColor: px.surfaceAlt,
                          foregroundColor: px.ink,
                          onPressed: _isBusy ? null : _exportAnkiCsv,
                        ),
                        PixelButton(
                          label: 'NHẬP FILE',
                          icon: Icons.upload_file,
                          backgroundColor: px.primary,
                          foregroundColor: px.ink,
                          onPressed: _isBusy ? null : _importFile,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 5. Notifications & TTS Audio
              PixelCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PixelSectionHeader(
                      title: 'THÔNG BÁO & PHÁT ÂM TTS',
                      icon: Icons.notifications_active_outlined,
                      accentColor: px.cyan,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Giọng mục tiêu chấm điểm phát âm',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment<String>(
                            value: 'en-US',
                            label: Text('US • Anh-Mỹ'),
                          ),
                          ButtonSegment<String>(
                            value: 'en-GB',
                            label: Text('UK • Anh-Anh'),
                          ),
                        ],
                        selected: {settings.targetAccent},
                        onSelectionChanged: (selected) {
                          if (selected.isEmpty) return;
                          notifier.updateSettings(
                            settings.copyWith(targetAccent: selected.first),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 20),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Nhắc ôn bài hàng ngày',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        kIsWeb
                            ? 'Bản Web chỉ hiện thông báo khi mở trình duyệt.'
                            : 'Giờ nhắc: ${settings.reminderHour.toString().padLeft(2, '0')}:${settings.reminderMinute.toString().padLeft(2, '0')}',
                      ),
                      value: !kIsWeb && settings.dailyReminderEnabled,
                      onChanged: kIsWeb
                          ? null
                          : (v) => notifier.updateSettings(
                                settings.copyWith(dailyReminderEnabled: v),
                              ),
                    ),
                    if (!kIsWeb)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.schedule, size: 17),
                          label: const Text('Đổi giờ nhắc'),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay(
                                hour: settings.reminderHour,
                                minute: settings.reminderMinute,
                              ),
                            );
                            if (picked != null) {
                              await notifier.updateSettings(
                                settings.copyWith(
                                  reminderHour: picked.hour,
                                  reminderMinute: picked.minute,
                                  dailyReminderEnabled: true,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Tự động đọc phát âm khi lật thẻ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      value: settings.autoPlayTts,
                      onChanged: (v) => notifier.updateSettings(
                        settings.copyWith(autoPlayTts: v),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Tra cứu & dịch ngữ cảnh Online',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Tự động dịch theo câu khi từ chưa có trong từ điển Offline.',
                      ),
                      value: settings.enableOnlineLookup,
                      onChanged: (v) => notifier.updateSettings(
                        settings.copyWith(enableOnlineLookup: v),
                      ),
                    ),
                    if (ttsService.isDiskCacheSupported)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.cleaning_services_outlined),
                          label: const Text('Xóa bộ nhớ đệm Audio TTS'),
                          onPressed: () async {
                            await ttsService.clearCache();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Đã dọn bộ nhớ đệm file Audio TTS!',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                valueText,
                style: TextStyle(
                  fontFamily: AppTheme.monoFont,
                  fontFamilyFallback: AppTheme.fontFallback,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: px.primaryBorder,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: Theme.of(context).sliderTheme.copyWith(
                  thumbShape: const PixelSliderThumbShape(size: 20),
                ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
