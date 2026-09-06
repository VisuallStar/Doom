import 'package:flutter/services.dart';
import 'package:android_intent_plus/android_intent.dart';

class AlarmService {
  static const _channel = MethodChannel('com.doom/device_actions');

  /// Set an alarm directly using native Android API (no screen control)
  Future<String> setAlarm({required int hour, required int minute, String? label}) async {
    try {
      final result = await _channel.invokeMethod<String>('setAlarmDirect', {
        'hour': hour,
        'minute': minute,
        'label': label ?? '',
      });
      return result ?? 'Alarm set for ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Error setting alarm: $e';
    }
  }

  /// Set a timer directly using native Android API (no screen control)
  Future<String> setTimer({required int seconds, String? label}) async {
    try {
      final result = await _channel.invokeMethod<String>('setTimerDirect', {
        'seconds': seconds,
        'label': label ?? '',
      });
      return result ?? 'Timer set';
    } catch (e) {
      return 'Error setting timer: $e';
    }
  }

  /// Set a reminder using the calendar
  Future<String> setReminder({
    required String title,
    String? description,
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minute,
  }) async {
    try {
      final dateTime = DateTime(year, month, day, hour, minute);
      final endTime = dateTime.add(const Duration(minutes: 30));
      final intent = AndroidIntent(
        action: 'android.intent.action.INSERT',
        data: 'content://com.android.calendar/events',
        arguments: {
          'beginTime': dateTime.millisecondsSinceEpoch,
          'endTime': endTime.millisecondsSinceEpoch,
          'title': title,
          'description': description ?? '',
          'hasAlarm': 1,
        },
      );
      await intent.launch();
      return 'Reminder set: "$title" on ${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')} at ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Error setting reminder: $e';
    }
  }
}
