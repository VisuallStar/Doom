import 'package:android_intent_plus/android_intent.dart';

class AlarmService {
  /// Set an alarm using Android's built-in alarm intent
  Future<String> setAlarm({
    required int hour,
    required int minute,
    String? label,
  }) async {
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.SET_ALARM',
        arguments: <String, dynamic>{
          'android.intent.extra.alarm.HOUR': hour,
          'android.intent.extra.alarm.MINUTES': minute,
          if (label != null) 'android.intent.extra.alarm.MESSAGE': label,
          'android.intent.extra.alarm.SKIP_UI': true,
        },
      );
      await intent.launch();
      final timeStr =
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      return 'Alarm set for $timeStr${label != null ? ' ($label)' : ''}';
    } catch (e) {
      return 'Error setting alarm: $e';
    }
  }

  /// Set a timer using Android's built-in timer intent
  Future<String> setTimer({
    required int seconds,
    String? label,
  }) async {
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.SET_TIMER',
        arguments: <String, dynamic>{
          'android.intent.extra.alarm.LENGTH': seconds,
          if (label != null) 'android.intent.extra.alarm.MESSAGE': label,
          'android.intent.extra.alarm.SKIP_UI': true,
        },
      );
      await intent.launch();
      final minutes = seconds ~/ 60;
      final secs = seconds % 60;
      return 'Timer set for ${minutes}m ${secs}s${label != null ? ' ($label)' : ''}';
    } catch (e) {
      return 'Error setting timer: $e';
    }
  }

  /// Set a calendar reminder using Android's calendar intent (background, no screen control)
  Future<String> setReminder({
    required String title,
    String? description,
    required int year,
    required int month,
    required int day,
    int hour = 9,
    int minute = 0,
  }) async {
    try {
      final startTime = DateTime(year, month, day, hour, minute);
      final endTime = startTime.add(const Duration(hours: 1));
      final intent = AndroidIntent(
        action: 'android.intent.action.INSERT',
        data: 'content://com.android.calendar/events',
        arguments: <String, dynamic>{
          'title': title,
          if (description != null) 'description': description,
          'beginTime': startTime.millisecondsSinceEpoch,
          'endTime': endTime.millisecondsSinceEpoch,
          'hasAlarm': 1,
        },
      );
      await intent.launch();
      final dateStr = '${year}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      final timeStr = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      return 'Reminder "$title" set for $dateStr at $timeStr.';
    } catch (e) {
      return 'Error setting reminder: $e';
    }
  }
}
