import 'package:flutter/services.dart';

class GalleryService {
  static const MethodChannel _channel = MethodChannel('com.privateagent/gallery');

  Future<String> shareImage({required String query}) async {
    try {
      final success = await _channel.invokeMethod<bool>('shareImage', {'query': query});
      if (success == true) {
        return 'Successfully opened gallery to share image for "$query"';
      }
      return 'Failed to share image';
    } catch (e) {
      return 'Error sharing image: $e';
    }
  }

  Future<String> shareImageToApp({required String query, required String appName}) async {
    try {
      final success = await _channel.invokeMethod<bool>('shareImageToApp', {
        'query': query,
        'appName': appName,
      });
      if (success == true) {
        return 'Successfully opened gallery to share image for "$query" to $appName';
      }
      return 'Failed to share image to $appName';
    } catch (e) {
      return 'Error sharing image to $appName: $e';
    }
  }

  Future<String> openGallery() async {
    try {
      final success = await _channel.invokeMethod<bool>('openGallery');
      if (success == true) {
        return 'Successfully opened gallery';
      }
      return 'Failed to open gallery';
    } catch (e) {
      return 'Error opening gallery: $e';
    }
  }
}
