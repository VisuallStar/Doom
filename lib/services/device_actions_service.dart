import 'package:flutter/services.dart';

/// Direct device control service using native Android APIs.
/// These actions execute instantly without screen automation.
class DeviceActionsService {
  static const _channel = MethodChannel('com.doom/device_actions');

  static const _torchChannel = MethodChannel('com.doom/torch');

  Future<String> toggleFlash(bool on) async {
    try {
      final result = await _torchChannel.invokeMethod<bool>('toggleTorch', {'enabled': on});
      return result == true ? (on ? 'Flashlight turned on' : 'Flashlight turned off') : 'Could not control flashlight';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String> setScreenTimeout(int seconds) async {
    try {
      final result = await _torchChannel.invokeMethod<bool>('setScreenTimeout', {'seconds': seconds});
      if (result == true) {
        final display = seconds >= 60 ? '${seconds ~/ 60} minute(s)' : '$seconds seconds';
        return 'Screen timeout set to $display';
      }
      return 'Could not set screen timeout. Grant WRITE_SETTINGS permission.';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String> youtubeSearch(String query) async {
    try {
      final result = await _channel.invokeMethod<String>('youtubeSearch', {'query': query});
      return result ?? 'YouTube search launched';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String> setBrightnessNative(int value) async {
    try {
      final result = await _channel.invokeMethod<String>('setBrightnessNative', {'value': value});
      return result ?? 'Brightness set';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String> setVolumeNative(int level) async {
    try {
      final result = await _channel.invokeMethod<String>('setVolumeNative', {'level': level});
      return result ?? 'Volume set';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String> setAlarmDirect({required int hour, required int minute, String? label}) async {
    try {
      final result = await _channel.invokeMethod<String>('setAlarmDirect', {
        'hour': hour, 'minute': minute, 'label': label ?? '',
      });
      return result ?? 'Alarm set';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String> setTimerDirect({required int seconds, String? label}) async {
    try {
      final result = await _channel.invokeMethod<String>('setTimerDirect', {
        'seconds': seconds, 'label': label ?? '',
      });
      return result ?? 'Timer set';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String> shareImage(String path, {String? packageName}) async {
    try {
      final result = await _channel.invokeMethod<String>('shareImage', {
        'path': path, 'package': packageName ?? '',
      });
      return result ?? 'Image shared';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String> makeDirectCall(String number) async {
    try {
      final result = await _channel.invokeMethod<String>('makeDirectCall', {'number': number});
      return result ?? 'Calling';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String> openWhatsApp({String? number, String? message}) async {
    try {
      final result = await _channel.invokeMethod<String>('openWhatsApp', {
        'number': number ?? '', 'message': message ?? '',
      });
      return result ?? 'WhatsApp opened';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String> openInstagram({String? username}) async {
    try {
      final result = await _channel.invokeMethod<String>('openInstagram', {
        'username': username ?? '',
      });
      return result ?? 'Instagram opened';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String> openSnapchat({String? username}) async {
    try {
      final result = await _channel.invokeMethod<String>('openSnapchat', {
        'username': username ?? '',
      });
      return result ?? 'Snapchat opened';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String> mediaControl(String action) async {
    try {
      final result = await _channel.invokeMethod<String>('mediaControl', {'action': action});
      return result ?? 'Media control executed';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String> openAppByName(String name) async {
    try {
      final result = await _channel.invokeMethod<String>('openAppByName', {'name': name});
      return result ?? 'App opened';
    } catch (e) { return 'Error: $e'; }
  }

  Future<String> youtubePlay(String query) async {
    try {
      final result = await _channel.invokeMethod<String>('youtubePlay', {'query': query});
      return result ?? 'Playing on YouTube';
    } catch (e) { return 'Error: $e'; }
  }
}
