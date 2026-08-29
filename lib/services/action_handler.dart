import '../models/agent_action.dart';
import '../models/chat_message.dart';
import 'app_launcher_service.dart';
import 'contacts_service.dart';
import 'communication_service.dart';
import 'alarm_service.dart';
import 'notes_service.dart';
import 'system_control_service.dart';
import 'shizuku_service.dart';
import 'screen_automation_service.dart';
import 'task_executor.dart';
import 'ai_service.dart';
import 'gallery_service.dart';

class ActionHandler {
  final AppLauncherService _appLauncher = AppLauncherService();
  final ContactsService _contacts = ContactsService();
  final CommunicationService _communication = CommunicationService();
  final AlarmService _alarm = AlarmService();
  final NotesService _notes = NotesService();
  final SystemControlService _systemControl = SystemControlService();
  final ShizukuService _shizuku = ShizukuService();
  final ScreenAutomationService _screenAutomation = ScreenAutomationService();
  final GalleryService _gallery = GalleryService();

  ShizukuService get shizuku => _shizuku;
  ScreenAutomationService get screenAutomation => _screenAutomation;

  /// The currently running task executor, if any
  TaskExecutor? _currentExecutor;

  /// Execute an action and return the result
  Future<AgentActionResult> execute(
    AgentAction action, {
    AiService? aiService,
    void Function(String)? onProgress,
  }) async {
    try {
      String result;

      switch (action.action) {
        case 'open_app':
          result = await _appLauncher.openApp(
            action.params['app_name'] as String? ?? '',
          );
          break;

        case 'open_app_section':
          final params = action.params.map((key, value) => MapEntry(key, value.toString()));
          result = await _appLauncher.openAppSection(
            appName: action.params['app_name'] as String? ?? '',
            section: action.params['section'] as String?,
            params: params,
          );
          break;

        case 'launch_package':
          final packageName = action.params['package_name'] as String? ?? '';
          result = await _appLauncher.openPackage(packageName);
          break;

        case 'make_call':
          result = await _communication.makeCall(
            contactName: action.params['contact_name'] as String?,
            phoneNumber: action.params['phone_number'] as String?,
          );
          break;

        case 'send_sms':
          result = await _communication.sendSms(
            contactName: action.params['contact_name'] as String?,
            phoneNumber: action.params['phone_number'] as String?,
            message: action.params['message'] as String? ?? '',
          );
          break;

        case 'search_contact':
          result = await _contacts.searchAndFormat(
            action.params['query'] as String? ?? '',
          );
          break;

        case 'set_alarm':
          result = await _alarm.setAlarm(
            hour: (action.params['hour'] as num?)?.toInt() ?? 0,
            minute: (action.params['minute'] as num?)?.toInt() ?? 0,
            label: action.params['label'] as String?,
          );
          break;

        case 'set_timer':
          result = await _alarm.setTimer(
            seconds: (action.params['seconds'] as num?)?.toInt() ?? 60,
            label: action.params['label'] as String?,
          );
          break;

        case 'set_volume':
          result = await _systemControl.setVolume(
            (action.params['level'] as num?)?.toInt() ?? 50,
          );
          break;

        case 'set_brightness':
          result = await _systemControl.setBrightness(
            (action.params['level'] as num?)?.toInt() ?? 50,
          );
          break;

        case 'run_adb_command':
          result = await _shizuku.runCommand(
            action.params['command'] as String? ?? '',
          );
          break;

        case 'send_email':
          result = await _communication.sendEmail(
            to: action.params['to'] as String? ?? '',
            cc: action.params['cc'] as String?,
            bcc: action.params['bcc'] as String?,
            subject: action.params['subject'] as String?,
            body: action.params['body'] as String?,
            attachmentPath: action.params['attachment_path'] as String?,
          );
          break;

        case 'open_url':
          result = await _appLauncher.openUrl(
            action.params['url'] as String? ?? '',
          );
          break;

        case 'get_datetime':
          result = _systemControl.getDateTime();
          break;

        case 'toggle_torch':
          result = await _systemControl.toggleTorch(
            action.params['enabled'] == true,
          );
          break;

        case 'whatsapp_call':
          result = await _communication.makeWhatsAppCall(
            contactName: action.params['contact_name'] as String?,
            phoneNumber: action.params['phone_number'] as String?,
          );
          break;

        case 'read_notifications':
          result = await _screenAutomation.readNotifications();
          break;

        case 'take_screenshot':
          result = await _systemControl.takeScreenshot();
          break;

        case 'screen_time':
          result = await _systemControl.getScreenTime();
          break;

        case 'set_screen_timeout':
          result = await _systemControl.setScreenTimeout(
            (action.params['seconds'] as num?)?.toInt() ?? 30,
          );
          break;

        case 'set_reminder':
          result = await _alarm.setReminder(
            title: action.params['title'] as String? ?? 'Reminder',
            description: action.params['description'] as String?,
            year: (action.params['year'] as num?)?.toInt() ?? DateTime.now().year,
            month: (action.params['month'] as num?)?.toInt() ?? DateTime.now().month,
            day: (action.params['day'] as num?)?.toInt() ?? DateTime.now().day,
            hour: (action.params['hour'] as num?)?.toInt() ?? 9,
            minute: (action.params['minute'] as num?)?.toInt() ?? 0,
          );
          break;

        case 'create_note':
          result = await _notes.createNote(
            title: action.params['title'] as String? ?? 'Untitled',
            content: action.params['content'] as String? ?? '',
          );
          break;

        case 'append_note':
          result = await _notes.appendNote(
            title: action.params['title'] as String? ?? 'Untitled',
            content: action.params['content'] as String? ?? '',
          );
          break;

        case 'list_notes':
          result = await _notes.listNotes();
          break;

        case 'read_note':
          result = await _notes.readNote(
            title: action.params['title'] as String? ?? '',
          );
          break;

        case 'delete_note':
          result = await _notes.deleteNote(
            title: action.params['title'] as String? ?? '',
          );
          break;

        case 'create_list':
          result = await _notes.createList(
            title: action.params['title'] as String? ?? 'Untitled List',
            items: (action.params['items'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
          );
          break;

        case 'add_to_list':
          result = await _notes.addToList(
            title: action.params['title'] as String? ?? 'Untitled List',
            items: (action.params['items'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
          );
          break;

        case 'check_list_item':
          result = await _notes.checkListItem(
            title: action.params['title'] as String? ?? '',
            item: action.params['item'] as String? ?? '',
          );
          break;

        case 'export_note':
          result = await _notes.exportNoteToPdf(
            title: action.params['title'] as String? ?? '',
          );
          break;

        case 'youtube_fullscreen':
          result = await _systemControl.youtubeFullscreen();
          break;

        case 'youtube_search':
          result = await _systemControl.youtubeSearch(
            action.params['query'] as String? ?? '',
          );
          break;

        case 'youtube_play':
          result = await _systemControl.youtubePlay(
            action.params['query'] as String? ?? '',
          );
          break;

        // ─── Screen Automation Actions ────────────────────────

        case 'read_screen':
          result = await _screenAutomation.getScreenDescription();
          break;

        case 'click_element':
          final text = action.params['text'] as String? ?? '';
          final success = await _screenAutomation.clickByText(text);
          result = success ? 'Clicked "$text"' : 'Could not find "$text" to click';
          break;

        case 'type_on_screen':
          final text = action.params['text'] as String? ?? '';
          final hint = action.params['field_hint'] as String?;
          final success = await _screenAutomation.typeText(text, fieldHint: hint);
          result = success ? 'Typed "$text"' : 'Could not type into field';
          break;

        case 'scroll_screen':
          final direction = action.params['direction'] as String? ?? 'down';
          final success = await _screenAutomation.scroll(direction);
          result = success ? 'Scrolled $direction' : 'Could not scroll';
          break;

        case 'press_back':
          final success = await _screenAutomation.pressBack();
          result = success ? 'Pressed back' : 'Could not press back';
          break;

        // ─── Multi-Step Task Execution ────────────────────────

        case 'execute_task':
          final goal = action.params['goal'] as String? ?? action.response;
          if (aiService == null) {
            result = 'AI service not available for task execution.';
            break;
          }
          _currentExecutor = TaskExecutor(
            aiService: aiService,
            screenService: _screenAutomation,
            appLauncher: _appLauncher,
            shizukuService: _shizuku,
            onProgress: onProgress,
          );
          result = await _currentExecutor!.executeTask(goal);
          _currentExecutor = null;
          break;

        case 'share_image':
          result = await _gallery.shareImageToApp(
            query: action.params['query'] as String? ?? '',
            appName: action.params['app_name'] as String? ?? '',
          );
          break;

        case 'open_gallery':
          result = await _gallery.openGallery();
          break;

        default:
          result = action.response;
      }

      return AgentActionResult(
        actionType: action.action,
        success: true,
        details: result,
      );
    } catch (e) {
      return AgentActionResult(
        actionType: action.action,
        success: false,
        details: 'Error: $e',
      );
    }
  }

  /// Cancel the currently running task
  void cancelTask() {
    _currentExecutor?.cancel();
  }
}
