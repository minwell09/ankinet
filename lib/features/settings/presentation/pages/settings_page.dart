import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/injection_container.dart';
import '../../../../core/database/local_database.dart';
import '../../../../core/database/offline_dictionary_database.dart';
import '../../../../core/services/tts_cache_service.dart';
import '../../../../core/settings/study_settings.dart';
import '../../../../core/srs/fsrs_weight_optimizer.dart';
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Cài Đặt FSRS • Từ Điển SQLite • Backup'),
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
            padding: const EdgeInsets.all(16),
            children: [
              // 1. Offline SQLite Dictionary (185k words) & Contextual Translation Pipeline
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📚 Từ Điển SQLite Offline (185k+ từ) & Chuỗi Dịch Ngữ Cảnh',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• Đóng gói riêng trong file SQLite asset (assets/nlp/offline_dict.db — không parse JSON lớn vào RAM):\n'
                        '  - Tổng mục từ: ${dictMeta['total_entries'] ?? '185,189'} từ Tiếng Anh\n'
                        '  - Định nghĩa EN ➔ VI: ${dictMeta['vi_entries'] ?? '104,717'} mục từ\n'
                        '  - Phiên âm IPA (Wiktionary + CMUdict): ${dictMeta['ipa_entries'] ?? '185,189'} mục\n'
                        '  - Bất quy tắc WordNet (Irregular Lemmas): ${dictMeta['irregular_lemmas'] ?? '5,519'} cặp\n'
                        '• Chuỗi dịch nghĩa: Từ điển SQLite Offline ➔ API/LLM (gửi kèm cả câu + glossary gốc từ) ➔ Lưu vào dict_cache theo (từ, hash câu).\n'
                        '• Giấy phép dữ liệu: ${dictMeta['license'] ?? 'CC BY-SA 4.0 (Wiktionary / MinhQND / WikDict / Skypedia) + CMUdict BSD + Princeton WordNet 3.0'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _geminiKeyCtrl,
                              obscureText: true,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                labelText:
                                    'Gemini API Key (Tùy chọn — dịch theo ngữ cảnh câu + glossary)',
                                hintText: 'AIzaSy... (Để trống sẽ dùng Google Translate GTX)',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
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
                                    'Đã lưu cấu hình Gemini API Key cho bộ dịch ngữ cảnh!',
                                  ),
                                ),
                              );
                            },
                            child: const Text('Lưu Key'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 2. Personal 17-Weight FSRS-4.5 Optimizer from revlog
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '🎯 Tối Ưu Bộ 17 Trọng Số FSRS Cá Nhân (Từ revlog)',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: settings.hasCustomFsrsWeights
                                ? colorScheme.tertiaryContainer
                                : colorScheme.surfaceContainerHighest,
                            label: Text(
                              settings.hasCustomFsrsWeights
                                  ? 'Đang dùng 17-Weight Cá Nhân'
                                  : 'Đang dùng 17-Weight Mặc Định',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tiến độ dữ liệu revlog: $revlogCount / ${FsrsWeightOptimizer.recommendedMinReviews} lượt ôn khuyến nghị '
                        '(${revlogCount >= FsrsWeightOptimizer.recommendedMinReviews ? "Đã đủ dữ liệu tối ưu chuẩn!" : "Khi đạt ~1,000 lượt ôn, bộ tối ưu sẽ khớp chính xác đường cong quên của riêng bạn; hiện có thể chạy thử với L2 regularization"}).',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: progressTo1000,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        'w[0..16] hiện tại: [${settings.effectiveFsrsWeights.map((w) => w.toStringAsFixed(4)).join(', ')}]',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                      ),
                      if (_lastOptResult != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Kết quả tối ưu gần nhất: ${_lastOptResult!.usableTransitions} cặp chuyển trạng thái • '
                          'Log-Loss: ${_lastOptResult!.initialLogLoss.toStringAsFixed(4)} ➔ ${_lastOptResult!.optimizedLogLoss.toStringAsFixed(4)} '
                          '(Cải thiện ${_lastOptResult!.improvementPercent.toStringAsFixed(2)}%)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: _isOptimizingFsrs
                                ? null
                                : () => _runFsrsOptimization(settings),
                            icon: const Icon(Icons.auto_graph),
                            label: Text(
                              _isOptimizingFsrs
                                  ? 'Đang tối ưu 17 trọng số (Isolate)...'
                                  : 'Tối ưu 17 trọng số FSRS từ revlog',
                            ),
                          ),
                          if (settings.hasCustomFsrsWeights)
                            OutlinedButton.icon(
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
                                      'Đã khôi phục 17 trọng số FSRS-4.5 mặc định!',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.restore),
                              label: const Text('Khôi phục 17 trọng số mặc định'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 3. FSRS & Daily Limits
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🧠 Tham Số Học FSRS-4.5 & Giới Hạn Hàng Ngày',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _SliderRow(
                        label: 'Giới hạn thẻ mới / ngày',
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
                        label: 'Giới hạn lượt ôn tối đa / ngày',
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
                        label: 'Mục tiêu tỉ lệ nhớ FSRS (Desired Retention)',
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
                        label: 'Ngưỡng đánh dấu thẻ Leech (số lần bấm Again)',
                        valueText: '${settings.leechThreshold} lần',
                        value: settings.leechThreshold.toDouble(),
                        min: 3,
                        max: 12,
                        divisions: 9,
                        onChanged: (v) => notifier.updateSettings(
                          settings.copyWith(leechThreshold: v.round()),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Tự động tạm ẩn (Suspend) thẻ Leech'),
                        subtitle: const Text(
                          'Khi một thẻ bị quên vượt ngưỡng Leech, tự động tạm ẩn để tránh tốn thời gian ôn',
                        ),
                        value: settings.suspendLeeches,
                        onChanged: (v) => notifier.updateSettings(
                          settings.copyWith(suspendLeeches: v),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Hiển thị câu điền khuyết (Surface-Form Cloze) ở mặt trước',
                        ),
                        subtitle: const Text(
                          'Tự động che đúng biến thể chữ xuất hiện trong câu (ví dụ câu có "running" hay "ran" đều được che chính xác dù thẻ lưu lemma "run")',
                        ),
                        value: settings.showClozeContext,
                        onChanged: (v) => notifier.updateSettings(
                          settings.copyWith(showClozeContext: v),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 4. Import / Export Anki (.apkg, CSV) & Periodic Web Backup Protection
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📦 Import / Export Anki (.apkg, CSV) & Nhắc Sao Lưu Định Kỳ',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Lần sao lưu JSON gần nhất: $lastBackupText\n'
                        '${kIsWeb ? "⚠️ Bạn đang chạy trên trình duyệt Web (IndexedDB): dữ liệu có thể bị xóa khi dọn lịch sử duyệt web. Hãy xuất file JSON định kỳ hoặc tải lên Google Drive." : "Ứng dụng lưu trữ SQLite nội bộ và nhắc sao lưu JSON định kỳ."}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      _SliderRow(
                        label: 'Chu kỳ nhắc sao lưu JSON định kỳ',
                        valueText: '${settings.backupReminderDays} ngày/lần',
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
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: _isBusy ? null : _exportBackupJson,
                            icon: const Icon(Icons.save_alt),
                            label: const Text(
                              'Backup Full (JSON / Lưu Google Drive)',
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _isBusy ? null : _exportAnkiApkg,
                            icon: const Icon(Icons.archive_outlined),
                            label: const Text('Xuất Anki (.apkg)'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _isBusy ? null : _exportAnkiCsv,
                            icon: const Icon(Icons.table_chart_outlined),
                            label: const Text('Xuất Anki (CSV/TSV)'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _isBusy ? null : _importFile,
                            icon: const Icon(Icons.upload_file),
                            label: const Text(
                              'Nhập (.apkg / CSV / JSON Backup)',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 5. Notifications & Audio TTS Cache (with explicit Web vs Android support checks)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🔔 Thông Báo Nhắc Ôn & Phát Âm TTS (${kIsWeb ? "Chế độ Web" : "Chế độ Android/Native"})',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          kIsWeb
                              ? 'Nhắc ôn bài hàng ngày (Alarm chạy ngầm chỉ hỗ trợ Android APK)'
                              : 'Nhắc ôn bài hàng ngày (Android Alarm)',
                        ),
                        subtitle: Text(
                          kIsWeb
                              ? 'Trên Web, trình duyệt không chạy AlarmManager ngầm khi đóng tab; ứng dụng sẽ hiển thị banner nhắc khi bạn mở trang.'
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
                            icon: const Icon(Icons.schedule),
                            label: const Text('Đổi giờ nhắc ôn bài'),
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
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Tự động đọc phát âm khi lật thẻ',
                        ),
                        subtitle: Text(
                          ttsService.isDiskCacheSupported
                              ? 'Android/iOS: Tự động tổng hợp và lưu cache file .wav vào bộ nhớ máy để phát tức thì offline.'
                              : 'Web: Phát âm qua Web Speech API (window.speechSynthesis) & Audio URL từ điển (Cache file .wav xuống đĩa chỉ hoạt động trên Android/iOS).',
                        ),
                        value: settings.autoPlayTts,
                        onChanged: (v) => notifier.updateSettings(
                          settings.copyWith(autoPlayTts: v),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Tra cứu ngữ cảnh Online/LLM & Cache vào dict_cache (word, sentence_hash)',
                        ),
                        subtitle: const Text(
                          'Từ ngoài từ điển SQLite hoặc khi bật Gemini Key sẽ được dịch theo câu ngữ cảnh và lưu vào dict_cache theo (từ, hash câu)',
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
                            label: const Text(
                              'Xóa bộ nhớ đệm file Audio TTS (.wav)',
                            ),
                            onPressed: () async {
                              await ttsService.clearCache();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Đã dọn bộ nhớ đệm file Audio TTS (.wav)!',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text(label)),
            Text(
              valueText,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
