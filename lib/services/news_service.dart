import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class NewsService {
  /// Fetches recent news headlines from a free API
  /// Uses Google News RSS feed via a simple parser
  static String _getCountryCode(String country) {
    final map = {
      'United States': 'US', 'United Kingdom': 'GB', 'India': 'IN',
      'Pakistan': 'PK', 'Canada': 'CA', 'Australia': 'AU',
      'Germany': 'DE', 'France': 'FR', 'Japan': 'JP',
      'China': 'CN', 'Brazil': 'BR', 'UAE': 'AE',
      'Saudi Arabia': 'SA', 'Turkey': 'TR', 'South Korea': 'KR',
      'Indonesia': 'ID', 'Nigeria': 'NG', 'South Africa': 'ZA',
      'Mexico': 'MX', 'Italy': 'IT', 'Spain': 'ES',
      'Russia': 'RU', 'Egypt': 'EG', 'Bangladesh': 'BD',
      'Philippines': 'PH', 'Malaysia': 'MY', 'Singapore': 'SG',
    };
    return map[country] ?? '';
  }

  Future<String> getNews({String? topic}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final country = prefs.getString('user_country') ?? '';
      // Map country names to Google News country codes
      final countryCode = _getCountryCode(country);
      final glParam = countryCode.isNotEmpty ? '&gl=$countryCode' : '';
      
      final url = topic != null && topic.isNotEmpty
          ? 'https://news.google.com/rss/search?q=${Uri.encodeComponent(topic)}&hl=en$glParam'
          : 'https://news.google.com/rss?hl=en$glParam';
      
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );
      
      if (response.statusCode == 200) {
        // Parse RSS XML for titles
        final body = response.body;
        final titles = <String>[];
        final regex = RegExp(r'<title><!\[CDATA\[(.*?)\]\]></title>');
        final matches = regex.allMatches(body);
        
        for (final match in matches.skip(1).take(8)) { // Skip feed title, take 8 headlines
          titles.add(match.group(1) ?? '');
        }
        
        // Also try standard <title>text</title> format
        if (titles.isEmpty) {
          final simpleRegex = RegExp(r'<item>.*?<title>(.*?)</title>', dotAll: true);
          final simpleMatches = simpleRegex.allMatches(body);
          for (final match in simpleMatches.take(8)) {
            titles.add(match.group(1)?.replaceAll(RegExp(r'<.*?>'), '') ?? '');
          }
        }
        
        if (titles.isEmpty) {
          return 'Unable to fetch news headlines at this time.';
        }
        
        final buffer = StringBuffer();
        final countryContext = country.isNotEmpty ? ' in $country' : '';
        buffer.writeln('📰 Recent News Headlines${topic != null ? " about $topic" : ""}$countryContext:');
        buffer.writeln();
        for (int i = 0; i < titles.length; i++) {
          buffer.writeln('${i + 1}. ${titles[i]}');
        }
        return buffer.toString();
      } else {
        return 'Unable to fetch news. HTTP status: ${response.statusCode}';
      }
    } catch (e) {
      return 'Unable to fetch news: $e';
    }
  }
}