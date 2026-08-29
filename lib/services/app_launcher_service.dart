import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:url_launcher/url_launcher.dart';

class AppLauncherService {
  List<AppInfo>? _cachedApps;

  /// Get all installed apps (cached), including system apps!
  Future<List<AppInfo>> getInstalledApps() async {
    _cachedApps ??= await InstalledApps.getInstalledApps(false, false);
    return _cachedApps!;
  }

  /// Clear app cache
  void clearCache() {
    _cachedApps = null;
  }

  /// Find apps matching a query
  Future<List<AppInfo>> searchApps(String query) async {
    final apps = await getInstalledApps();
    final lowerQuery = query.toLowerCase();
    return apps.where((app) {
      return app.name.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// Open an app by name (fuzzy match)
  Future<String> openApp(String appName) async {
    final matches = await searchApps(appName);

    if (matches.isEmpty) {
      return 'Could not find app "$appName". Try being more specific.';
    }

    // Try exact match first
    AppInfo? target;
    for (final app in matches) {
      if (app.name.toLowerCase() == appName.toLowerCase()) {
        target = app;
        break;
      }
    }
    target ??= matches.first;

    try {
      await InstalledApps.startApp(target.packageName);
      return 'Opened ${target.name}';
    } catch (e) {
      return 'Error opening ${target.name}: $e';
    }
  }

  /// Open an app by exact package name
  Future<String> openPackage(String packageName) async {
    try {
      await InstalledApps.startApp(packageName);
      return 'Launched $packageName';
    } catch (e) {
      return 'Error launching $packageName: $e';
    }
  }

  /// Open a URL
  Future<String> openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return 'Opened $url';
      }
      return 'Cannot open $url';
    } catch (e) {
      return 'Error opening URL: $e';
    }
  }

  /// Open a specific section of an app
  Future<String> openAppSection({required String appName, String? section, Map<String, String>? params}) async {
    final uriStr = _getDeepLink(appName, section, params);
    if (uriStr != null) {
      try {
        final uri = Uri.parse(uriStr);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return 'Opened ${section ?? "app"} in $appName';
        }
      } catch (e) {
        // Fall back to opening main app
      }
    }
    return await openApp(appName);
  }

  String? _getDeepLink(String appName, String? section, Map<String, String>? params) {
    final lowerApp = appName.toLowerCase();
    final lowerSection = section?.toLowerCase() ?? '';
    
    if (lowerApp.contains('instagram')) {
      if (lowerSection == 'dm' || lowerSection == 'dms' || lowerSection == 'messages' || lowerSection == 'chat') return 'instagram://direct_inbox';
      if (lowerSection == 'explore') return 'instagram://explore';
      if (lowerSection == 'profile' && params?['name'] != null) return 'instagram://user?username=${params!['name']}';
      return 'instagram://';
    }
    
    if (lowerApp.contains('whatsapp')) {
      if (params?['number'] != null) return 'whatsapp://send?phone=${params!['number']}';
      return 'whatsapp://';
    }
    
    if (lowerApp.contains('twitter') || lowerApp == 'x') {
      if (lowerSection == 'dm' || lowerSection == 'dms' || lowerSection == 'messages') return 'twitter://messages';
      return 'twitter://';
    }
    
    if (lowerApp.contains('messenger') || lowerApp.contains('facebook messenger')) {
      return 'fb-messenger://';
    }
    
    if (lowerApp.contains('telegram')) {
      if (params?['name'] != null) return 'tg://resolve?domain=${params!['name']}';
      return 'tg://';
    }
    
    if (lowerApp.contains('gmail')) {
      if (lowerSection == 'compose') {
        final to = params?['email'] ?? '';
        final subject = params?['subject'] ?? '';
        final body = params?['body'] ?? '';
        return 'googlegmail://co?to=$to&subject=$subject&body=$body';
      }
      return 'googlegmail://';
    }
    
    if (lowerApp.contains('spotify')) {
      if (lowerSection == 'search' && params?['query'] != null) return 'spotify://search/${params!['query']}';
      return 'spotify://';
    }
    
    if (lowerApp.contains('maps') || lowerApp.contains('google maps')) {
      if (params?['destination'] != null) return 'google.navigation:q=${params!['destination']}';
      return 'google.navigation:';
    }
    
    return null;
  }
}
