import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    try {
      tz.initializeTimeZones();
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      await _plugin.initialize(initSettings);
      _initialized = true;
    } catch (_) {}
  }

  Future<bool> scheduleDailyReviewReminder({
    required int hour,
    required int minute,
    required int dueCount,
  }) async {
    if (kIsWeb) return false;
    await init();
    if (!_initialized) return false;

    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();

      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      const androidDetails = AndroidNotificationDetails(
        'vocab_anki_daily_review',
        'Nhắc ôn từ vựng FSRS',
        channelDescription: 'Thông báo nhắc ôn thẻ từ vựng VocabAnki hàng ngày',
        importance: Importance.high,
        priority: Priority.high,
      );

      await _plugin.zonedSchedule(
        1001,
        'VocabAnki — Đến giờ ôn từ vựng!',
        dueCount > 0
            ? 'Bạn có $dueCount thẻ đến hạn ôn hôm nay. Giữ chuỗi streak nhé!'
            : 'Dành 5 phút ôn tập từ vựng và gốc từ cùng FSRS nhé!',
        scheduled,
        const NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelDailyReminder() async {
    if (kIsWeb || !_initialized) return;
    try {
      await _plugin.cancel(1001);
    } catch (_) {}
  }
}
