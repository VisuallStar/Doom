import 'dart:convert';
import 'package:http/http.dart' as http;

class NewsService {
  /// Fetches recent news headlines from a free API
  /// Uses Google News RSS feed via a simple parser
  Future<String> getNews({String? topic}) async {
    try {
      final query = topic ?? 'latest';
      // Use Google News RSS
      final url = topic != null && topic.isNotEmpty
          ? 'https://news.google.com/rss/search?q=${Uri.encodeComponent(topic)}&hl=en'
          : 'https://news.google.com/rss?hl=en';
      
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
        buffer.writeln('📰 Recent News Headlines${topic != null ? " about $topic" : ""}:');
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