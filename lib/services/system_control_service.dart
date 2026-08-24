import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class SystemControlService {
  SystemControlService() {
    // Don't show system volume UI when we control it
    VolumeController().showSystemUI = false;
  }

  /// Set media volume (0-100)
  Future<String> setVolume(int level) async {
    try {
      final volume = (level / 100).clamp(0.0, 1.0);
      VolumeController().setVolume(volume);
      return 'Volume set to $level%';
    } catch (e) {
      return 'Error setting volume: $e';
    }
  }

  /// Get current volume (0-100)
  Future<int> getVolume() async {
    try {
      final volume = await VolumeController().getVolume();
      return (volume * 100).round();
    } catch (e) {
      return -1;
    }
  }

  /// Set screen brightness (0-100)
  Future<String> setBrightness(int level) async {
    try {
      final brightness = (level / 100).clamp(0.0, 1.0);
      await ScreenBrightness().setScreenBrightness(brightness);
      return 'Brightness set to $level%';
    } catch (e) {
      return 'Error setting brightness: $e';
    }
  }

  /// Get current brightness (0-100)
  Future<int> getBrightness() async {
    try {
      final brightness = await ScreenBrightness().current;
      return (brightness * 100).round();
    } catch (e) {
      return -1;
    }
  }

  /// Set screen timeout duration in seconds
  /// Common values: 15, 30, 60, 120, 300, 600 (seconds)
  Future<String> setScreenTimeout(int seconds) async {
    try {
      final result = await _torchChannel.invokeMethod<bool>(
        'setScreenTimeout',
        {'seconds': seconds},
      );
      if (result == true) {
        final display = seconds >= 60 ? '${seconds ~/ 60} minute(s)' : '$seconds seconds';
        return 'Screen timeout set to $display.';
      }
      return 'Could not set screen timeout. You may need to grant WRITE_SETTINGS permission.';
    } catch (e) {
      return 'Error setting screen timeout: $e';
    }
  }

  /// Toggle the device flashlight/torch
  static const _torchChannel = MethodChannel('com.privateagent/torch');
  
  Future<String> toggleTorch(bool enabled) async {
    try {
      final result = await _torchChannel.invokeMethod<bool>(
        'toggleTorch',
        {'enabled': enabled},
      );
      if (result == true) {
        return enabled ? 'Flashlight turned on.' : 'Flashlight turned off.';
      }
      return 'Could not control flashlight.';
    } catch (e) {
      return 'Error controlling flashlight: $e';
    }
  }

  /// Get current date, time, and day of week
  String getDateTime() {
    final now = DateTime.now();
    final dateFormat = DateFormat('EEEE, MMMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');
    return 'Today is ${dateFormat.format(now)}.\nThe current time is ${timeFormat.format(now)}.';
  }

  /// Take a screenshot using the accessibility service (no clicks needed)
  static const _accessibilityChannel = MethodChannel('com.privateagent/accessibility');

  Future<String> takeScreenshot() async {
    try {
      final result = await _accessibilityChannel.invokeMethod<String>('takeScreenshot');
      if (result != null && result.isNotEmpty) {
        return 'Screenshot captured successfully.';
      }
      return 'Could not capture screenshot. Accessibility service may not be running.';
    } catch (e) {
      return 'Error taking screenshot: $e';
    }
  }

  /// Get current screen time / usage stats (via Android UsageStatsManager)
  Future<String> getScreenTime() async {
    try {
      final result = await _torchChannel.invokeMethod<String>('getScreenTime');
      if (result != null && result.isNotEmpty) {
        return result;
      }
      return 'Screen time data is not available. Please grant usage access permission.';
    } catch (e) {
      return 'Could not get screen time: $e';
    }
  }

  /// Open YouTube and search for a query directly using deep link (no clicking needed)
  Future<String> youtubeSearch(String query) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final uri = Uri.parse('https://www.youtube.com/results?search_query=$encodedQuery');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return 'Opened YouTube search for "$query".';
      }
      // Fallback: try vnd.youtube intent
      final ytUri = Uri.parse('vnd.youtube://results?search_query=$encodedQuery');
      if (await canLaunchUrl(ytUri)) {
        await launchUrl(ytUri, mode: LaunchMode.externalApplication);
        return 'Opened YouTube search for "$query".';
      }
      return 'Could not open YouTube. Is it installed?';
    } catch (e) {
      return 'Error searching YouTube: $e';
    }
  }

  /// Play a specific YouTube video by search query (opens first result)
  Future<String> youtubePlay(String query) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      // Use YouTube search URL which will show results ready to play
      final uri = Uri.parse('https://www.youtube.com/results?search_query=$encodedQuery');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return 'Opened YouTube with "$query". Tap the first video to play it.';
      }
      return 'Could not open YouTube.';
    } catch (e) {
      return 'Error playing YouTube video: $e';
    }
  }
}
