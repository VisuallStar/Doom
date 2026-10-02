import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:just_audio/just_audio.dart';
import 'package:archive/archive.dart';

/// Kokoro TTS Service using sherpa-onnx.
///
/// The int8 model archive is bundled inside the APK as a Flutter asset.
/// On first launch it is extracted to the app's documents directory
/// (one-time, ~15-30 s). No internet connection is ever required.
class KokoroTtsService {
  static const String _modelDirName = 'kokoro_tts_model';

  /// Asset path of the bundled model archive.
  static const String _bundledArchiveAsset =
      'assets/kokoro/kokoro-int8-en-v0_19.tar.bz2';

  /// Subfolder name inside the tar archive.
  static const String _archiveSubdir = 'kokoro-int8-en-v0_19';

  // ─── Voice catalog ─────────────────────────────────────────────────
  static const Map<int, Map<String, String>> voices = {
    0:  {'name': 'Heart (af)', 'gender': 'Female', 'accent': 'American', 'tag': 'af'},
    1:  {'name': 'Bella',      'gender': 'Female', 'accent': 'American', 'tag': 'af_bella'},
    2:  {'name': 'Nicole',     'gender': 'Female', 'accent': 'American', 'tag': 'af_nicole'},
    3:  {'name': 'Sarah',      'gender': 'Female', 'accent': 'American', 'tag': 'af_sarah'},
    4:  {'name': 'Sky',        'gender': 'Female', 'accent': 'American', 'tag': 'af_sky'},
    5:  {'name': 'Adam',       'gender': 'Male',   'accent': 'American', 'tag': 'am_adam'},
    6:  {'name': 'Michael',    'gender': 'Male',   'accent': 'American', 'tag': 'am_michael'},
    7:  {'name': 'Emma',       'gender': 'Female', 'accent': 'British',  'tag': 'bf_emma'},
    8:  {'name': 'Isabella',   'gender': 'Female', 'accent': 'British',  'tag': 'bf_isabella'},
    9:  {'name': 'George',     'gender': 'Male',   'accent': 'British',  'tag': 'bm_george'},
    10: {'name': 'Lewis',      'gender': 'Male',   'accent': 'British',  'tag': 'bm_lewis'},
  };

  // ─── Engine state ──────────────────────────────────────────────────
  sherpa_onnx.OfflineTts? _tts;
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isModelReady = false;
  bool _isExtracting = false;
  bool _isSpeaking = false;
  double _extractProgress = 0.0;
  int _selectedVoiceId = 5; // Default: Adam
  double _speed = 1.0;
  String? _modelDir;
  String? _audioCacheDir;

  bool get isModelReady => _isModelReady;
  bool get isExtracting => _isExtracting;
  bool get isSpeaking => _isSpeaking;
  double get extractProgress => _extractProgress;
  int get selectedVoiceId => _selectedVoiceId;
  double get speed => _speed;

  // ─── Initialization ────────────────────────────────────────────────

  /// Initialize the service: load prefs, check/extract model, init engine.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedVoiceId = prefs.getInt('kokoro_voice_id') ?? 5;
    _speed = prefs.getDouble('kokoro_speed') ?? 1.0;

    final appDir = await getApplicationDocumentsDirectory();
    _modelDir = '${appDir.path}/$_modelDirName';
    _audioCacheDir = '${appDir.path}/kokoro_audio_cache';

    await Directory(_audioCacheDir!).create(recursive: true);

    // Check if model already extracted from a previous launch
    _isModelReady = await _allModelFilesExist();

    if (!_isModelReady) {
      // First launch — extract bundled model from assets
      await _extractBundledModel();
    }

    if (_isModelReady) {
      await _initTtsEngine();
    }
  }

  /// Check that all required model files are present on disk.
  Future<bool> _allModelFilesExist() async {
    if (_modelDir == null) return false;
    for (final f in ['model.onnx', 'voices.bin', 'tokens.txt']) {
      if (!await File('$_modelDir/$f').exists()) return false;
    }
    final espeakDir = Directory('$_modelDir/espeak-ng-data');
    if (!await espeakDir.exists()) return false;
    final items = await espeakDir.list().toList();
    return items.isNotEmpty;
  }

  /// Extract the bundled tar.bz2 asset to the app documents directory.
  /// This runs once on first launch (~15-30 s on a mid-range phone).
  Future<void> _extractBundledModel({void Function(double)? onProgress}) async {
    if (_isExtracting) return;
    _isExtracting = true;
    _extractProgress = 0.0;

    try {
      final dir = Directory(_modelDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // --- Step 1: Copy asset to a temp file (rootBundle → File) ---
      debugPrint('KokoroTTS: Loading bundled model from assets...');
      _extractProgress = 0.05;
      onProgress?.call(_extractProgress);

      final byteData = await rootBundle.load(_bundledArchiveAsset);
      final tempArchivePath = '${_modelDir!}/_temp_archive.tar.bz2';
      final tempFile = File(tempArchivePath);
      await tempFile.writeAsBytes(
        byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
        flush: true,
      );

      _extractProgress = 0.30;
      onProgress?.call(_extractProgress);

      // --- Step 2: Extract tar.bz2 in an isolate ---
      debugPrint('KokoroTTS: Extracting model archive...');
      await compute(_extractTarBz2Isolate, {
        'archivePath': tempArchivePath,
        'outputPath': _modelDir!,
      });

      _extractProgress = 0.85;
      onProgress?.call(_extractProgress);

      // --- Step 3: Move files from subdirectory to model root ---
      final extractedSubdir = Directory('${_modelDir!}/$_archiveSubdir');
      if (await extractedSubdir.exists()) {
        await for (final entity in extractedSubdir.list()) {
          final name = entity.path.split('/').last;
          final target = '${_modelDir!}/$name';
          if (entity is File) {
            await entity.copy(target);
            await entity.delete();
          } else if (entity is Directory) {
            final targetDir = Directory(target);
            if (await targetDir.exists()) {
              await targetDir.delete(recursive: true);
            }
            await entity.rename(target);
          }
        }
        if (await extractedSubdir.exists()) {
          await extractedSubdir.delete(recursive: true);
        }
      }

      // --- Step 4: Clean up temp archive ---
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      _extractProgress = 1.0;
      onProgress?.call(_extractProgress);

      _isModelReady = await _allModelFilesExist();
      _isExtracting = false;

      debugPrint('KokoroTTS: Model extraction complete. Ready=$_isModelReady');
    } catch (e) {
      debugPrint('KokoroTTS: Extraction error: $e');
      _isExtracting = false;
    }
  }

  /// Static isolate worker — decompresses bz2, decodes tar, writes files.
  static void _extractTarBz2Isolate(Map<String, String> args) {
    final archivePath = args['archivePath']!;
    final outputPath = args['outputPath']!;

    final bytes = File(archivePath).readAsBytesSync();

    // Decompress BZip2
    final tarBytes = BZip2Decoder().decodeBytes(bytes);

    // Decode Tar
    final archive = TarDecoder().decodeBytes(tarBytes);

    // Write files
    for (final file in archive) {
      final name = file.name;
      if (file.isFile) {
        final out = File('$outputPath/$name');
        out.createSync(recursive: true);
        out.writeAsBytesSync(file.content as List<int>);
      } else {
        Directory('$outputPath/$name').createSync(recursive: true);
      }
    }
  }

  // ─── TTS engine ────────────────────────────────────────────────────

  /// Initialize the sherpa_onnx OfflineTts engine.
  Future<bool> _initTtsEngine() async {
    if (_modelDir == null) return false;
    try {
      _tts?.free();
      _tts = null;

      final config = sherpa_onnx.OfflineTtsConfig(
        model: sherpa_onnx.OfflineTtsModelConfig(
          kokoro: sherpa_onnx.OfflineTtsKokoroModelConfig(
            model: '$_modelDir/model.onnx',
            voices: '$_modelDir/voices.bin',
            tokens: '$_modelDir/tokens.txt',
            dataDir: '$_modelDir/espeak-ng-data',
            lengthScale: _speed,
          ),
          numThreads: 2,
          debug: false,
        ),
      );

      _tts = sherpa_onnx.OfflineTts(config);
      debugPrint('KokoroTTS: Engine initialized — '
          'speakers: ${_tts!.numSpeakers}, sampleRate: ${_tts!.sampleRate}');
      return true;
    } catch (e) {
      debugPrint('KokoroTTS: Engine init failed: $e');
      _tts = null;
      return false;
    }
  }

  // ─── Voice & speed settings ────────────────────────────────────────

  Future<void> setVoice(int voiceId) async {
    _selectedVoiceId = voiceId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('kokoro_voice_id', voiceId);
  }

  Future<void> setSpeed(double speed) async {
    _speed = speed.clamp(0.5, 2.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('kokoro_speed', _speed);
    if (_isModelReady && _tts != null) {
      await _initTtsEngine();
    }
  }

  // ─── Speech generation ─────────────────────────────────────────────

  /// Generate speech from text and play it.
  Future<bool> speak(String text) async {
    if (!_isModelReady || _tts == null || text.isEmpty) return false;

    try {
      _isSpeaking = true;

      final audio = _tts!.generate(
        text: text,
        sid: _selectedVoiceId,
        speed: _speed,
      );

      if (audio.samples.isEmpty) {
        debugPrint('KokoroTTS: Generated empty audio');
        _isSpeaking = false;
        return false;
      }

      final wavPath = await _writeWavFile(audio.samples, audio.sampleRate);
      if (wavPath == null) {
        _isSpeaking = false;
        return false;
      }

      await _audioPlayer.setFilePath(wavPath);
      await _audioPlayer.play();
      await _audioPlayer.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );

      _isSpeaking = false;
      return true;
    } catch (e) {
      debugPrint('KokoroTTS: Speak error: $e');
      _isSpeaking = false;
      return false;
    }
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
    _isSpeaking = false;
  }

  // ─── WAV writer ────────────────────────────────────────────────────

  Future<String?> _writeWavFile(Float32List samples, int sampleRate) async {
    try {
      final int16 = Int16List(samples.length);
      for (int i = 0; i < samples.length; i++) {
        int16[i] = (samples[i].clamp(-1.0, 1.0) * 32767).round();
      }

      final dataBytes = int16.buffer.asUint8List();
      final header = _buildWavHeader(dataBytes.length, sampleRate, 1, 16);

      final path =
          '$_audioCacheDir/tts_${DateTime.now().millisecondsSinceEpoch}.wav';
      final sink = File(path).openWrite();
      sink.add(header);
      sink.add(dataBytes);
      await sink.flush();
      await sink.close();

      _cleanupAudioCache();
      return path;
    } catch (e) {
      debugPrint('KokoroTTS: WAV write error: $e');
      return null;
    }
  }

  Uint8List _buildWavHeader(
      int dataSize, int sampleRate, int channels, int bits) {
    final byteRate = sampleRate * channels * (bits ~/ 8);
    final blockAlign = channels * (bits ~/ 8);
    final h = ByteData(44);
    // RIFF
    h.setUint8(0, 0x52); h.setUint8(1, 0x49);
    h.setUint8(2, 0x46); h.setUint8(3, 0x46);
    h.setUint32(4, 36 + dataSize, Endian.little);
    h.setUint8(8, 0x57); h.setUint8(9, 0x41);
    h.setUint8(10, 0x56); h.setUint8(11, 0x45);
    // fmt
    h.setUint8(12, 0x66); h.setUint8(13, 0x6D);
    h.setUint8(14, 0x74); h.setUint8(15, 0x20);
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little);
    h.setUint16(22, channels, Endian.little);
    h.setUint32(24, sampleRate, Endian.little);
    h.setUint32(28, byteRate, Endian.little);
    h.setUint16(32, blockAlign, Endian.little);
    h.setUint16(34, bits, Endian.little);
    // data
    h.setUint8(36, 0x64); h.setUint8(37, 0x61);
    h.setUint8(38, 0x74); h.setUint8(39, 0x61);
    h.setUint32(40, dataSize, Endian.little);
    return h.buffer.asUint8List();
  }

  void _cleanupAudioCache() {
    if (_audioCacheDir == null) return;
    try {
      final dir = Directory(_audioCacheDir!);
      if (!dir.existsSync()) return;
      final files = dir.listSync().whereType<File>()
          .where((f) => f.path.endsWith('.wav')).toList();
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (final f in files.skip(5)) {
        try { f.deleteSync(); } catch (_) {}
      }
    } catch (_) {}
  }

  // ─── Model info ────────────────────────────────────────────────────

  String? get modelDir => _modelDir;

  Future<double> getModelSizeMb() async {
    if (_modelDir == null) return 0;
    double total = 0;
    final dir = Directory(_modelDir!);
    if (!await dir.exists()) return 0;
    await for (final e in dir.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    return total / (1024 * 1024);
  }

  /// Re-extract the model from bundled assets (e.g. after cache clear).
  Future<void> reExtractModel({void Function(double)? onProgress}) async {
    // Delete existing extracted files
    if (_modelDir != null) {
      final dir = Directory(_modelDir!);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    _isModelReady = false;
    _tts?.free();
    _tts = null;

    await _extractBundledModel(onProgress: onProgress);

    if (_isModelReady) {
      await _initTtsEngine();
    }
  }

  void dispose() {
    _audioPlayer.dispose();
    _tts?.free();
    _tts = null;
  }
}
