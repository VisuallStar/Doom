import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'kokoro_tts_service.dart';

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _fallbackTts = FlutterTts();
  final KokoroTtsService kokoroTts = KokoroTtsService();
  bool _isInitialized = false;
  bool _isListening = false;
  bool _useKokoroTts = true; // Prefer Kokoro by default

  bool get isListening => _isListening;
  bool get useKokoroTts => _useKokoroTts;
  
  Future<void> init() async {
    if (_isInitialized) return;

    _isInitialized = await _speech.initialize(
      onError: (error) {
        _isListening = false;
      },
    );

    // Configure fallback Google TTS
    await _fallbackTts.setLanguage('en-US');
    await _fallbackTts.setSpeechRate(0.5);
    await _fallbackTts.setVolume(1.0);
    await _fallbackTts.setPitch(1.0);

    // Initialize Kokoro TTS
    await kokoroTts.init();
    
    // Load TTS preference
    final prefs = await SharedPreferences.getInstance();
    _useKokoroTts = prefs.getBool('use_kokoro_tts') ?? true;
  }

  /// Toggle between Kokoro and Google TTS
  Future<void> setUseKokoroTts(bool value) async {
    _useKokoroTts = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_kokoro_tts', value);
  }

  /// Start listening for speech. Returns transcribed text via callback.
  Future<void> startListening({
    required Function(String) onResult,
    required Function() onDone,
  }) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return;

    _isListening = true;

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        if (result.finalResult) {
          _isListening = false;
          onResult(result.recognizedWords);
          onDone();
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.confirmation,
        partialResults: false,
      ),
    );
  }

  /// Stop listening
  Future<void> stopListening() async {
    _isListening = false;
    await _speech.stop();
  }

  /// Speak text aloud - uses Kokoro TTS if available and enabled,
  /// otherwise falls back to the system Google TTS.
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    
    if (_useKokoroTts && kokoroTts.isModelReady) {
      // Use Kokoro TTS via sherpa_onnx — real offline TTS
      final success = await kokoroTts.speak(text);
      if (!success) {
        // If Kokoro fails for any reason, fall back to Google TTS
        await _fallbackTts.speak(text);
      }
    } else {
      // Fallback to Google TTS
      await _fallbackTts.speak(text);
    }
  }

  /// Preview a voice with a sample phrase
  Future<void> previewVoice(int voiceId) async {
    final voiceInfo = KokoroTtsService.voices[voiceId];
    final name = voiceInfo?['name'] ?? 'Agent';
    await kokoroTts.setVoice(voiceId);
    await speak("Hi, I'm $name. How can I help you today?");
  }

  /// Stop speaking
  Future<void> stopSpeaking() async {
    await kokoroTts.stop();
    await _fallbackTts.stop();
  }

  void dispose() {
    _speech.stop();
    _fallbackTts.stop();
    kokoroTts.dispose();
  }
}
