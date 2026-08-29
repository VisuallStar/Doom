import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_action.dart';

class AiResponse {
  final String content;
  final int totalTokens;
  AiResponse(this.content, this.totalTokens);
}

class AiService {
  static const String _defaultBaseUrl = 'https://generativelanguage.googleapis.com/v1beta/openai';
  static const String _defaultModel = 'gemini-2.0-flash';
  static const String nvidiaBaseUrl = 'https://integrate.api.nvidia.com/v1';
  static const String nvidiaDefaultModel = 'z-ai/glm-5.2';

  /// Free, general-purpose chat endpoints verified in NVIDIA's NIM catalog.
  /// The live /models response is intersected with this list so unavailable or
  /// non-chat models never appear in PrivateAgent's NVIDIA model picker.
  static const List<String> nvidiaFreeChatModels = [
    'z-ai/glm-5.2',
    'nvidia/nemotron-3-nano-30b-a3b',
    'nvidia/nemotron-3-super-120b-a12b',
    'nvidia/nemotron-3-ultra-550b-a55b',
    'nvidia/nvidia-nemotron-nano-9b-v2',
    'openai/gpt-oss-20b',
    'openai/gpt-oss-120b',
    'meta/llama-3.3-70b-instruct',
    'meta/llama-3.2-3b-instruct',
    'meta/llama-3.1-8b-instruct',
    'meta/llama-3.1-70b-instruct',
    'mistralai/mistral-nemotron',
    'deepseek-ai/deepseek-v4-flash',
    'deepseek-ai/deepseek-v4-pro',
  ];

  static bool isNvidiaBaseUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    return uri?.host.toLowerCase() == 'integrate.api.nvidia.com';
  }

  static List<String> filterNvidiaFreeModels(Iterable<String> models) {
    final availableModels = models.toSet();
    return nvidiaFreeChatModels
        .where(availableModels.contains)
        .toList(growable: false);
  }

  String? _apiKey;
  String _baseUrl = _defaultBaseUrl;
  String _model = _defaultModel;
  int _maxSteps = 15;
  bool _disableMaxSteps = false;
  double _temperature = 1.0;
  int _maxTokens = 1024;
  bool _useScreenCompression = true;
  bool _useSystemPrompt = true;
  final List<Map<String, String>> _conversationHistory = [];

  static const String _systemPrompt = '''
You are PrivateAgent, a helpful AI assistant on an Android phone.

For device actions, respond with ONLY a JSON object:
{"action": "action_name", "params": {"key": "value"}, "response": "What you say"}

INSTANT ACTIONS (no screen interaction needed):
- open_app: {"app_name": "YouTube"} - Only to open an app, nothing else
- open_app_section: {"app_name": "Instagram", "section": "dm"} - Open a specific section of an app
- make_call: {"contact_name": "Mom"} or {"phone_number": "123"}
- send_sms: {"contact_name": "John", "message": "Hi"} - Sends SMS directly in background
- search_contact: {"query": "John"}
- set_alarm: {"hour": 7, "minute": 30, "label": "Wake up"}
- set_timer: {"seconds": 300, "label": "Eggs"}
- set_reminder: {"title": "Meeting", "year": 2026, "month": 8, "day": 25, "hour": 14, "minute": 0, "description": "Team sync"}
- set_volume: {"level": 50} (0-100)
- set_brightness: {"level": 50} (0-100)
- set_screen_timeout: {"seconds": 120} (15/30/60/120/300/600)
- get_datetime: {}
- toggle_torch: {"enabled": true}
- whatsapp_call: {"contact_name": "John"}
- read_notifications: {}
- send_email: {"to": "x@y.com", "subject": "Hi", "body": "Hello", "cc": "z@y.com", "bcc": "a@y.com"} - Compose and open email
- take_screenshot: {}
- screen_time: {}
- youtube_search: {"query": "funny cats"} - Opens YouTube search
- youtube_play: {"query": "lofi music"} - Opens YouTube and auto-plays
- youtube_fullscreen: {} - Makes current YouTube video fullscreen
- create_note: {"title": "Shopping List", "content": "Milk, eggs, bread"} - Creates a note in background
- append_note: {"title": "Shopping List", "content": "Butter"} - Appends to an existing note
- list_notes: {} - Lists all saved notes
- read_note: {"title": "Shopping List"} - Reads a saved note
- delete_note: {"title": "Shopping List"} - Deletes a note
- create_list: {"title": "Shopping List", "items": ["Milk", "Eggs", "Bread"]} - Creates a checklist
- add_to_list: {"title": "Shopping List", "items": ["Butter"]} - Add items to a list
- check_list_item: {"title": "Shopping List", "item": "Milk"} - Mark item as done
- read_screen: {}
- press_back: {}
- share_image: {"app_name": "WhatsApp", "query": "sunset photo"} - Share an image to an app
- open_gallery: {} - Open the gallery/photos app

MULTI-STEP (needs screen interaction):
- execute_task: {"goal": "full description"} - Auto opens apps, clicks, types, scrolls

RULES:
1. Use instant actions whenever possible. They are fast and reliable.
2. YouTube → Use youtube_search or youtube_play by default. Use execute_task ONLY when the user specifically wants auto-play.
3. Volume, brightness, timeout, notifications, time, torch, screenshot → ALWAYS instant action.
4. Notes → ALWAYS use create_note, append_note, read_note, list_notes. NEVER use execute_task for notes.
5. SMS → ALWAYS use send_sms (sends directly). NEVER use execute_task for SMS.
6. Reminders → ALWAYS use set_reminder. NEVER use execute_task for reminders.
7. DO NOT open apps unnecessarily. If the user just asks a question, respond with text.
8. Lists → ALWAYS use create_list, add_to_list, check_list_item. NEVER use execute_task for lists.
9. Use execute_task ONLY when the task needs screen interaction (navigating menus, clicking buttons). Always include the app name in the goal.

Examples:
- "play music on youtube" → youtube_play {"query": "music"}
- "search cats youtube" → youtube_search {"query": "cats"}
- "volume 80" → set_volume {"level": 80}
- "set screen timeout 5 minutes" → set_screen_timeout {"seconds": 300}
- "notifications" → read_notifications
- "call mom on whatsapp" → whatsapp_call {"contact_name": "Mom"}
- "write hello in notes" → create_note {"title": "Note", "content": "hello"}
- "add milk to shopping list" → append_note {"title": "Shopping List", "content": "milk"}
- "what notes do I have" → list_notes {}
- "text john hey" → send_sms {"contact_name": "John", "message": "hey"}
- "remind me to call doctor tomorrow at 3pm" → set_reminder {"title": "Call doctor", "year": 2026, "month": 8, "day": 26, "hour": 15, "minute": 0}
- "what's the time" → get_datetime
- "open camera" → open_app {"app_name": "Camera"}
- "make youtube fullscreen" → youtube_fullscreen {}
- "make a shopping list with milk eggs bread" → create_list {"title": "Shopping List", "items": ["Milk", "Eggs", "Bread"]}
- "add butter to shopping list" → add_to_list {"title": "Shopping List", "items": ["Butter"]}
- "mark milk as done" → check_list_item {"title": "Shopping List", "item": "Milk"}
- "export my shopping list" → export_note {"title": "Shopping List"}

For questions/chat, respond with plain text. Do NOT use any action.
''';

  static const String _chatSystemPrompt = '''
You are PrivateAgent, a helpful conversational AI assistant. 
Provide direct, natural, and friendly text responses. You cannot perform device actions or run tools. 
Answer questions, explain concepts, brainstorm, write emails/messages, and chat with the user in plain text or markdown format.
''';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('api_key');
    _baseUrl = prefs.getString('api_base_url') ?? _defaultBaseUrl;
    _model = prefs.getString('api_model') ?? _defaultModel;
    _maxSteps = prefs.getInt('api_max_steps') ?? 15;
    _disableMaxSteps = prefs.getBool('api_disable_max_steps') ?? false;
    _temperature = prefs.getDouble('api_temperature') ?? 1.0;
    _maxTokens = prefs.getInt('api_max_tokens') ?? 1024;
    _useScreenCompression = prefs.getBool('api_use_screen_compression') ?? true;
    _useSystemPrompt = prefs.getBool('api_use_system_prompt') ?? true;
  }

  Future<void> saveSettings({
    required String apiKey,
    String? baseUrl,
    String? model,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Clean up the API key in case the user pasted "Bearer sk-..."
    String cleanApiKey = apiKey.trim();
    if (cleanApiKey.toLowerCase().startsWith('bearer ')) {
      cleanApiKey = cleanApiKey.substring(7).trim();
    }

    _apiKey = cleanApiKey;
    await prefs.setString('api_key', cleanApiKey);

    if (baseUrl != null && baseUrl.isNotEmpty) {
      _baseUrl = baseUrl;
      await prefs.setString('api_base_url', baseUrl);
    }
    if (model != null && model.isNotEmpty) {
      _model = model;
      await prefs.setString('api_model', model);
    }
  }

  Future<void> saveMaxSteps(int steps) async {
    final prefs = await SharedPreferences.getInstance();
    _maxSteps = steps;
    await prefs.setInt('api_max_steps', steps);
  }

  Future<void> saveDisableMaxSteps(bool disable) async {
    final prefs = await SharedPreferences.getInstance();
    _disableMaxSteps = disable;
    await prefs.setBool('api_disable_max_steps', disable);
  }

  Future<void> saveAdvancedSettings({
    required double temperature,
    required int maxTokens,
    required bool useScreenCompression,
    required bool useSystemPrompt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _temperature = temperature;
    _maxTokens = maxTokens;
    _useScreenCompression = useScreenCompression;
    _useSystemPrompt = useSystemPrompt;
    await prefs.setDouble('api_temperature', temperature);
    await prefs.setInt('api_max_tokens', maxTokens);
    await prefs.setBool('api_use_screen_compression', useScreenCompression);
    await prefs.setBool('api_use_system_prompt', useSystemPrompt);
  }

  bool get isConfigured => _apiKey != null && _apiKey!.isNotEmpty;
  String get baseUrl => _baseUrl;
  String get model => _model;
  String get apiKey => _apiKey ?? '';
  int get maxSteps => _disableMaxSteps ? 999 : _maxSteps;
  int get rawMaxSteps => _maxSteps; // For the slider UI
  bool get disableMaxSteps => _disableMaxSteps;
  double get temperature => _temperature;
  int get maxTokens => _maxTokens;
  bool get useScreenCompression => _useScreenCompression;
  bool get useSystemPrompt => _useSystemPrompt;

  int get _effectiveMaxTokens {
    // GLM is a reasoning model. With the app's 1,024-token default it can
    // consume the whole budget reasoning and finish without visible content.
    if (isNvidiaBaseUrl(_baseUrl) &&
        _model == nvidiaDefaultModel &&
        _maxTokens < 4096) {
      return 4096;
    }
    // Gemini models support larger context, ensure reasonable output
    if (_baseUrl.contains('generativelanguage.googleapis.com') && _maxTokens < 2048) {
      return 2048;
    }
    return _maxTokens;
  }

  void clearHistory() {
    _conversationHistory.clear();
  }

  void addHistoryMessage(String role, String content) {
    _conversationHistory.add({'role': role, 'content': content});
    if (_conversationHistory.length > 20) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 20);
    }
  }

  /// Send a message to the AI and get a response.
  Future<String> sendMessage(String message, {bool isAgentMode = true}) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key is not configured. Please go to Settings.');
    }

    // Add ONLY the text to the persistent conversation history to save tokens.
    _conversationHistory.add({'role': 'user', 'content': message});

    // Keep conversation history manageable (last 20 messages)
    if (_conversationHistory.length > 20) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 20);
    }

    try {
      // Build the prompt including system instructions
      final systemPrompt = isAgentMode ? _systemPrompt : _chatSystemPrompt;
      final messages = [
        if (_useSystemPrompt) {'role': 'system', 'content': systemPrompt},
        ..._conversationHistory,
      ];

      String requestUrl = _baseUrl;
      if (requestUrl.endsWith('/chat/completions')) {
        requestUrl = requestUrl; // User already included it
      } else {
        if (requestUrl.endsWith('/')) {
          requestUrl = '${requestUrl}chat/completions';
        } else {
          requestUrl = '$requestUrl/chat/completions';
        }
      }

      final requestBody = jsonEncode({
        'model': _model,
        'messages': messages,
        'temperature': _temperature,
        'max_tokens': _effectiveMaxTokens,
      });

      developer.log(
        'API Request: $requestUrl\n$requestBody',
        name: 'AiService',
      );

      final response = await http
          .post(
            Uri.parse(requestUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
              'HTTP-Referer': 'https://github.com/orailnoor/private-agent',
              'X-Title': 'PrivateAgent',
            },
            body: requestBody,
          )
          .timeout(const Duration(minutes: 30));

      developer.log(
        'API Response [${response.statusCode}]: ${response.body}',
        name: 'AiService',
      );

      if (response.statusCode != 200) {
        String errorMessage = response.body;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            if (decoded['error'] is Map<String, dynamic>) {
              errorMessage =
                  decoded['error']['message']?.toString() ?? response.body;
            } else if (decoded['error'] is String) {
              errorMessage = decoded['error'];
            }
          }
        } catch (_) {
          // ignore parsing errors, use raw body
        }
        throw Exception('API error (${response.statusCode}): $errorMessage');
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || !data.containsKey('choices')) {
        throw Exception('Unexpected API response format: $data');
      }

      String assistantMessage =
          data['choices'][0]['message']['content'] as String;

      // Strip <think> blocks commonly produced by reasoning models
      assistantMessage = assistantMessage
          .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
          .trim();

      if (assistantMessage.trim().isEmpty) {
        throw Exception(
          'API returned an empty response. This may be due to rate limits or API instability.',
        );
      }

      _conversationHistory.add({
        'role': 'assistant',
        'content': assistantMessage,
      });

      return assistantMessage;
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Network error: $e');
    }
  }

  /// Send a message and stream the response chunk-by-chunk.
  Stream<String> sendMessageStream(
    String message, {
    bool isAgentMode = true,
  }) async* {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key is not configured. Please go to Settings.');
    }

    _conversationHistory.add({'role': 'user', 'content': message});

    if (_conversationHistory.length > 20) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 20);
    }

    try {
      final systemPrompt = isAgentMode ? _systemPrompt : _chatSystemPrompt;
      final messages = [
        if (_useSystemPrompt) {'role': 'system', 'content': systemPrompt},
        ..._conversationHistory,
      ];

      String requestUrl = _baseUrl;
      if (requestUrl.endsWith('/chat/completions')) {
        requestUrl = requestUrl;
      } else {
        if (requestUrl.endsWith('/')) {
          requestUrl = '${requestUrl}chat/completions';
        } else {
          requestUrl = '$requestUrl/chat/completions';
        }
      }

      final client = http.Client();
      final request = http.Request('POST', Uri.parse(requestUrl));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
        'HTTP-Referer': 'https://github.com/orailnoor/private-agent',
        'X-Title': 'PrivateAgent',
      });

      request.body = jsonEncode({
        'model': _model,
        'messages': messages,
        'temperature': _temperature,
        'max_tokens': _effectiveMaxTokens,
        'stream': true,
      });

      final response = await client
          .send(request)
          .timeout(const Duration(minutes: 30));

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        String errorMessage = body;
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) {
            if (decoded['error'] is Map<String, dynamic>) {
              errorMessage = decoded['error']['message']?.toString() ?? body;
            } else if (decoded['error'] is String) {
              errorMessage = decoded['error'];
            }
          }
        } catch (_) {}
        client.close();
        throw Exception('API error (${response.statusCode}): $errorMessage');
      }

      final accumulatedContent = StringBuffer();
      bool inThinkBlock = false;

      // Listen to response stream
      final lineStream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lineStream) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;
        if (trimmedLine.startsWith('data:')) {
          final dataStr = trimmedLine.substring(5).trim();
          if (dataStr == '[DONE]') break;
          try {
            final json = jsonDecode(dataStr);
            if (json is Map && json['choices'] is List) {
              final choices = json['choices'] as List;
              if (choices.isNotEmpty) {
                final choice = choices[0];
                if (choice is! Map) continue;
                final rawDelta = choice['delta'];
                final delta = rawDelta is Map ? rawDelta : const {};
                final rawContent = delta['content'];
                if (rawContent is String && rawContent.isNotEmpty) {
                  final content = rawContent;
                  accumulatedContent.write(content);

                  // Handle <think> block stripping on the fly for better stream styling
                  if (content.contains('<think>')) {
                    inThinkBlock = true;
                    // If there is text before <think>, yield it
                    final parts = content.split('<think>');
                    if (parts[0].isNotEmpty) {
                      yield parts[0];
                    }
                  } else if (content.contains('</think>')) {
                    inThinkBlock = false;
                    // If there is text after </think>, yield it
                    final parts = content.split('</think>');
                    if (parts.length > 1 && parts[1].isNotEmpty) {
                      yield parts[1];
                    }
                  } else if (!inThinkBlock) {
                    yield content;
                  }
                }
                if (choice['finish_reason'] != null) break;
              }
            }
          } catch (_) {
            // Ignore incomplete chunks
          }
        }
      }

      client.close();

      // Clean up final accumulated response and add to history
      String finalResponse = accumulatedContent.toString().trim();
      finalResponse = finalResponse
          .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
          .trim();

      if (finalResponse.isEmpty) {
        throw Exception(
          'The model finished without a visible answer. Increase Max Tokens '
          'or try another NVIDIA model.',
        );
      }
      _conversationHistory.add({'role': 'assistant', 'content': finalResponse});
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Network error: $e');
    }
  }

  /// Send a task execution message — no conversation history, low temperature, limited tokens.
  /// This is much faster and cheaper than sendMessage.
  Future<AiResponse> sendTaskMessage(String systemPrompt, String prompt) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key is not configured. Please go to Settings.');
    }

    int maxRetries = 4;
    int currentTry = 0;

    while (true) {
      try {
        currentTry++;
        final messages = [
          if (_useSystemPrompt) {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': prompt},
        ];

        String requestUrl = _baseUrl;
        if (!requestUrl.endsWith('/chat/completions')) {
          if (requestUrl.endsWith('/')) {
            requestUrl = '${requestUrl}chat/completions';
          } else {
            requestUrl = '$requestUrl/chat/completions';
          }
        }

        final response = await http
            .post(
              Uri.parse(requestUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $_apiKey',
                'HTTP-Referer': 'https://github.com/orailnoor/private-agent',
                'X-Title': 'PrivateAgent',
                'Connection': 'keep-alive',
              },
              body: jsonEncode({
                'model': _model,
                'messages': messages,
                'temperature': 0.3, // Lower temp for more deterministic execution
                'max_tokens': _effectiveMaxTokens,
              }),
            )
            .timeout(const Duration(seconds: 60));

        if (response.statusCode != 200) {
          String errorMessage = response.body;
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map<String, dynamic>) {
              if (decoded['error'] is Map<String, dynamic>) {
                errorMessage = decoded['error']['message'] ?? response.body;
              } else if (decoded['error'] is String) {
                errorMessage = decoded['error'];
              }
            }
          } catch (_) {
            // ignore parsing errors, use raw body
          }
          throw Exception('API error (${response.statusCode}): $errorMessage');
        }

        final data = jsonDecode(response.body);
        if (data is! Map<String, dynamic> || !data.containsKey('choices')) {
          throw Exception('Unexpected API response format: $data');
        }
        String content = data['choices'][0]['message']['content'] as String;

        // Strip <think> blocks commonly produced by reasoning models
        content = content
            .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
            .trim();

        if (content.trim().isEmpty) {
          throw Exception(
            'API returned an empty response. This may be due to strict rate limits or safety filters.',
          );
        }

        int tokens = 0;
        if (data.containsKey('usage') &&
            data['usage']['total_tokens'] != null) {
          tokens = data['usage']['total_tokens'] as int;
        }
        return AiResponse(content, tokens);
      } catch (e) {
        if (currentTry > maxRetries) {
          if (e is Exception) rethrow;
          throw Exception('Network error after $maxRetries retries: $e');
        }
        int delaySeconds = 3 * currentTry;
        developer.log(
          'API call failed ($e), retrying $currentTry/$maxRetries in $delaySeconds seconds...',
          name: 'PrivateAgent',
        );
        await Future.delayed(Duration(seconds: delaySeconds));
      }
    }
  }

  /// Parse the AI response to check if it's an action or plain text
  AgentAction? parseAction(String response) {
    // Try to parse as JSON action
    try {
      final trimmed = response.trim();
      // Handle if the response is wrapped in code fences
      String jsonStr = trimmed;
      if (trimmed.startsWith('```')) {
        final lines = trimmed.split('\n');
        lines.removeAt(0); // Remove opening fence
        if (lines.isNotEmpty && lines.last.trim() == '```') {
          lines.removeLast(); // Remove closing fence
        }
        jsonStr = lines.join('\n').trim();
      }

      // If it looks like JSON but is missing a closing brace (common with some local models)
      if (jsonStr.startsWith('{') && !jsonStr.endsWith('}')) {
        jsonStr += '\n}';
      }

      if (jsonStr.startsWith('{') && jsonStr.contains('"action"')) {
        try {
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          if (json.containsKey('action')) {
            return AgentAction.fromJson(json);
          }
        } catch (e) {
          // If it still fails, it might be deeply truncated, try adding another brace
          if (e.toString().contains('Unexpected end of input')) {
            jsonStr += '\n}';
            final json = jsonDecode(jsonStr) as Map<String, dynamic>;
            if (json.containsKey('action')) {
              return AgentAction.fromJson(json);
            }
          }
        }
      }
    } catch (_) {
      // Not JSON, it's plain text conversation
    }
    return null;
  }

  /// Fetches available models from the provider's /models endpoint
  Future<List<String>> fetchAvailableModels(
    String baseUrl,
    String apiKey,
  ) async {
    try {
      String cleanBaseUrl = baseUrl;
      // Many providers host it at /models, but some require the base URL without /chat/completions logic
      if (cleanBaseUrl.endsWith('/chat/completions')) {
        cleanBaseUrl = cleanBaseUrl.replaceAll('/chat/completions', '');
      }

      final response = await http.get(
        Uri.parse('$cleanBaseUrl/models'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<String> models;
        if (data is Map && data.containsKey('data')) {
          final modelsList = data['data'] as List;
          models = modelsList.map((m) => m['id'].toString()).toList();
        } else if (data is List) {
          models = data.map((m) => m['id'].toString()).toList();
        } else {
          return [];
        }

        if (isNvidiaBaseUrl(cleanBaseUrl)) {
          return filterNvidiaFreeModels(models);
        }
        models.sort();
        return models;
      }
      return [];
    } catch (e) {
      print('Error fetching models: $e');
      return [];
    }
  }
}
