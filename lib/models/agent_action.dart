class AgentAction {
  final String action;
  final Map<String, dynamic> params;
  final String response;

  AgentAction({
    required this.action,
    required this.params,
    required this.response,
  });

  factory AgentAction.fromJson(Map<String, dynamic> json) {
    return AgentAction(
      action: json['action'] as String? ?? 'general_query',
      params: json['params'] as Map<String, dynamic>? ?? {},
      response: json['response'] as String? ?? '',
    );
  }

  static const List<String> availableActions = [
    'open_app',
    'make_call',
    'send_sms',
    'send_email',
    'search_contact',
    'set_alarm',
    'set_timer',
    'set_reminder',
    'set_volume',
    'set_brightness',
    'toggle_torch',
    'set_screen_timeout',
    'read_notifications',
    'read_screen',
    'take_screenshot',
    'get_datetime',
    'get_news',
    'get_screen_time',
    'youtube_search',
    'youtube_play',
    'youtube_fullscreen',
    'whatsapp_call',
    'whatsapp_message',
    'share_image',
    'share_text',
    'create_note',
    'append_note',
    'read_note',
    'list_notes',
    'delete_note',
    'launch_package',
    'open_url',
    'media_control',
    'run_adb_command',
    'execute_task',
    'general_query',
  ];
}
