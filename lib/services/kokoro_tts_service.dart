import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:just_audio/just_audio.dart';
import 'package:archive/archive.dart';

/// Kokoro TTS Service using sherpa-onnx
/// Downloads the Kokoro int8 ONNX model on first use and runs inference locally.
/// Generates real speech audio via the OfflineTts API and plays it with just_audio.
class KokoroTtsService {
  static const String _modelDirName = 'kokoro_tts_model';

  // The int8 quantized model is ~98 MB (vs 305 MB for full float) — much more
  // phone-friendly while keeping the same 11 voices and quality.
  static const String _modelArchiveUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-en-v0_19.tar.bz2';

  // Subfolder name inside the tar archive
  static const String _archiveSubdir = 'kokoro-int8-en-v0_19';

  // All available Kokoro v0.19 English voices with speaker IDs.
  static const Map<int, Map<String, String>> voices = {
    0: {'name': 'Heart (af)', 'gender': 'Female', 'accent': 'American', 'tag': 'af'},
    1: {'name': 'Bella', 'gender': 'Female', 'accent': 'American', 'tag': 'af_bella'},
    2: {'name': 'Nicole', 'gender': 'Female', 'accent': 'American', 'tag': 'af_nicole'},
    3: {'name': 'Sarah', 'gender': 'Female', 'accent': 'American', 'tag': 'af_sarah'},
    4: {'name': 'Sky', 'gender': 'Female', 'accent': 'American', 'tag': 'af_sky'},
    5: {'name': 'Adam', 'gender': 'Male', 'accent': 'American', 'tag': 'am_adam'},
    6: {'name': 'Michael', 'gender': 'Male', 'accent': 'American', 'tag': 'am_michael'},
    7: {'name': 'Emma', 'gender': 'Female', 'accent': 'British', 'tag': 'bf_emma'},
    8: {'name': 'Isabella', 'gender': 'Female', 'accent': 'British', 'tag': 'bf_isabella'},
    9: {'name': 'George', 'gender': 'Male', 'accent': 'British', 'tag': 'bm_george'},
    10: {'name': 'Lewis', 'gender': 'Male', 'accent': 'British', 'tag': 'bm_lewis'},
  };

  // Singleton sherpa_onnx TTS engine instance
  sherpa_onnx.OfflineTts? _tts;
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isModelReady = false;
  bool _isDownloading = false;
  bool _isSpeaking = false;
  double _downloadProgress = 0.0;
  int _selectedVoiceId = 5; // Default: Adam
  double _speed = 1.0;
  String? _modelDir;
  String? _audioCacheDir;

  bool get isModelReady => _isModelReady;
  bool get isDownloading => _isDownloading;
  bool get isSpeaking => _isSpeaking;
  double get downloadProgress => _downloadProgress;
  int get selectedVoiceId => _selectedVoiceId;
  double get speed => _speed;

  /// Initialize the service, check if model exists, and load preferences.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedVoiceId = prefs.getInt('kokoro_voice_id') ?? 5;
    _speed = prefs.getDouble('kokoro_speed') ?? 1.0;

    final appDir = await getApplicationDocumentsDirectory();
    _modelDir = '${appDir.path}/$_modelDirName';
    _audioCacheDir = '${appDir.path}/kokoro_audio_cache';

    // Create audio cache dir
    final cacheDir = Directory(_audioCacheDir!);
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    // Check if all required model files exist
    _isModelReady = await _allModelFilesExist();

    // If model is ready, initialize the TTS engine
    if (_isModelReady) {
      await _initTtsEngine();
    }
  }

  /// Check that all required model files are present.
  Future<bool> _allModelFilesExist() async {
    if (_modelDir == null) return false;
    final requiredFiles = ['model.onnx', 'voices.bin', 'tokens.txt'];
    for (final f in requiredFiles) {
      if (!await File('$_modelDir/$f').exists()) return false;
    }
    // Also check espeak-ng-data directory has content
    final espeakDir = Directory('$_modelDir/espeak-ng-data');
    if (!await espeakDir.exists()) return false;
    final contents = await espeakDir.list().length;
    return contents > 0;
  }

  /// Initialize the sherpa_onnx OfflineTts engine with the Kokoro config.
  Future<bool> _initTtsEngine() async {
    if (_modelDir == null) return false;

    try {
      // Free previous engine if exists
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
      debugPrint('KokoroTTS: Engine initialized successfully. '
          'Speakers: ${_tts!.numSpeakers}, '
          'Sample rate: ${_tts!.sampleRate}');
      return true;
    } catch (e) {
      debugPrint('KokoroTTS: Failed to initialize engine: $e');
      _tts = null;
      return false;
    }
  }

  /// Set the selected voice and persist the preference.
  Future<void> setVoice(int voiceId) async {
    _selectedVoiceId = voiceId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('kokoro_voice_id', voiceId);
  }

  /// Set the speech speed (0.5 = slow, 1.0 = normal, 2.0 = fast).
  Future<void> setSpeed(double speed) async {
    _speed = speed.clamp(0.5, 2.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('kokoro_speed', _speed);
    // Re-initialize engine with new speed if it's running
    if (_isModelReady && _tts != null) {
      await _initTtsEngine();
    }
  }

  /// Download the Kokoro model archive and extract all required files.
  /// Uses dart:io HttpClient which properly follows HTTP 302 redirects
  /// (GitHub releases redirect to Azure CDN).
  Future<bool> downloadModel({void Function(double)? onProgress}) async {
    if (_isDownloading) return false;
    _isDownloading = true;
    _downloadProgress = 0.0;

    try {
      final dir = Directory(_modelDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // If model files already exist, skip download
      if (await _allModelFilesExist()) {
        _isModelReady = true;
        _isDownloading = false;
        await _initTtsEngine();
        return true;
      }

      // --- Step 1: Download the tar.bz2 archive (~98 MB for int8) ---
      debugPrint('KokoroTTS: Downloading model archive...');
      final archivePath = '${_modelDir!}/model_archive.tar.bz2';
      final archiveFile = File(archivePath);

      final downloadOk = await _downloadFileWithRedirects(
        _modelArchiveUrl,
        archiveFile,
        (progress) {
          // Download is 80% of total progress
          _downloadProgress = progress * 0.80;
          onProgress?.call(_downloadProgress);
        },
      );

      if (!downloadOk) {
        throw Exception('Failed to download model archive');
      }

      // --- Step 2: Extract tar.bz2 using the archive package ---
      debugPrint('KokoroTTS: Extracting model archive...');
      _downloadProgress = 0.82;
      onProgress?.call(_downloadProgress);

      await _extractTarBz2(archiveFile, dir);

      _downloadProgress = 0.95;
      onProgress?.call(_downloadProgress);

      // --- Step 3: Move files from subdirectory to model dir ---
      // The archive extracts to kokoro-int8-en-v0_19/ subfolder
      final extractedSubdir = Directory('${_modelDir!}/$_archiveSubdir');
      if (await extractedSubdir.exists()) {
        await for (final entity in extractedSubdir.list()) {
          final targetName = entity.path.split('/').last;
          final targetPath = '${_modelDir!}/$targetName';
          if (entity is File) {
            await entity.copy(targetPath);
            await entity.delete();
          } else if (entity is Directory) {
            // For espeak-ng-data directory, move it
            final targetDir = Directory(targetPath);
            if (await targetDir.exists()) {
              await targetDir.delete(recursive: true);
            }
            await entity.rename(targetPath);
          }
        }
        // Remove the now-empty subdirectory
        if (await extractedSubdir.exists()) {
          await extractedSubdir.delete(recursive: true);
        }
      }

      // --- Step 4: Cleanup archive file ---
      if (await archiveFile.exists()) {
        await archiveFile.delete();
      }

      _downloadProgress = 1.0;
      onProgress?.call(_downloadProgress);

      // Verify all files exist
      _isModelReady = await _allModelFilesExist();

      if (_isModelReady) {
        await _initTtsEngine();
      }

      _isDownloading = false;
      return _isModelReady;
    } catch (e) {
      debugPrint('KokoroTTS: Download error: $e');
      _isDownloading = false;
      return false;
    }
  }

  /// Download a file using dart:io HttpClient, which properly follows
  /// HTTP 302 redirects (required for GitHub releases → Azure CDN).
  Future<bool> _downloadFileWithRedirects(
    String url,
    File targetFile,
    void Function(double) onProgress,
  ) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);

      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        debugPrint('KokoroTTS: HTTP ${response.statusCode} for $url');
        client.close();
        return false;
      }

      final contentLength = response.contentLength;
      int receivedBytes = 0;
      final sink = targetFile.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (contentLength > 0) {
          onProgress(receivedBytes / contentLength);
        }
      }

      await sink.flush();
      await sink.close();
      client.close();
      return true;
    } catch (e) {
      debugPrint('KokoroTTS: Download error for $url: $e');
      client?.close();
      return false;
    }
  }

  /// Extract a .tar.bz2 archive using the Dart `archive` package.
  /// Runs in an isolate to avoid blocking the UI thread.
  Future<void> _extractTarBz2(File archiveFile, Directory outputDir) async {
    await compute(_extractTarBz2Isolate, {
      'archivePath': archiveFile.path,
      'outputPath': outputDir.path,
    });
  }

  /// Static method for isolate execution — extracts tar.bz2 archive.
  static void _extractTarBz2Isolate(Map<String, String> args) {
    final archivePath = args['archivePath']!;
    final outputPath = args['outputPath']!;

    final bytes = File(archivePath).readAsBytesSync();

    // Step 1: Decompress BZip2
    final bz2Decoder = BZip2Decoder();
    final tarBytes = bz2Decoder.decodeBytes(bytes);

    // Step 2: Decode Tar
    final tarDecoder = TarDecoder();
    final archive = tarDecoder.decodeBytes(tarBytes);

    // Step 3: Extract files
    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final outputFile = File('$outputPath/$filename');
        outputFile.createSync(recursive: true);
        outputFile.writeAsBytesSync(file.content as List<int>);
      } else {
        Directory('$outputPath/$filename').createSync(recursive: true);
      }
    }
  }

  /// Generate speech from text and play it.
  /// Returns true if speech was generated and playback started.
  Future<bool> speak(String text) async {
    if (!_isModelReady || _tts == null || text.isEmpty) return false;

    try {
      _isSpeaking = true;

      // Generate audio using sherpa_onnx
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

      // Write samples to WAV file
      final wavPath = await _writeWavFile(audio.samples, audio.sampleRate);
      if (wavPath == null) {
        _isSpeaking = false;
        return false;
      }

      // Play the WAV file using just_audio
      await _audioPlayer.setFilePath(wavPath);
      await _audioPlayer.play();

      // Wait for playback to complete
      await _audioPlayer.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );

      _isSpeaking = false;
      return true;
    } catch (e) {
      debugPrint('KokoroTTS: Speech generation error: $e');
      _isSpeaking = false;
      return false;
    }
  }

  /// Stop any ongoing playback.
  Future<void> stop() async {
    await _audioPlayer.stop();
    _isSpeaking = false;
  }

  /// Write Float32List PCM samples to a WAV file.
  /// Returns the path to the written WAV file.
  Future<String?> _writeWavFile(Float32List samples, int sampleRate) async {
    try {
      // Convert float32 samples [-1.0, 1.0] to int16 PCM
      final int16Samples = Int16List(samples.length);
      for (int i = 0; i < samples.length; i++) {
        final clamped = samples[i].clamp(-1.0, 1.0);
        int16Samples[i] = (clamped * 32767).round();
      }

      final dataBytes = int16Samples.buffer.asUint8List();
      final wavBytes = _buildWavHeader(dataBytes.length, sampleRate, 1, 16);

      // Write to cache file
      final filePath = '$_audioCacheDir/tts_${DateTime.now().millisecondsSinceEpoch}.wav';
      final file = File(filePath);
      final sink = file.openWrite();
      sink.add(wavBytes);
      sink.add(dataBytes);
      await sink.flush();
      await sink.close();

      // Clean up old cache files (keep only last 5)
      _cleanupAudioCache();

      return filePath;
    } catch (e) {
      debugPrint('KokoroTTS: WAV write error: $e');
      return null;
    }
  }

  /// Build a standard 44-byte WAV header.
  Uint8List _buildWavHeader(
    int dataSize,
    int sampleRate,
    int numChannels,
    int bitsPerSample,
  ) {
    final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final blockAlign = numChannels * (bitsPerSample ~/ 8);
    final fileSize = 36 + dataSize;

    final header = ByteData(44);
    // RIFF chunk
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    // fmt sub-chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // Sub-chunk size
    header.setUint16(20, 1, Endian.little);  // PCM format
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    // data sub-chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    return header.buffer.asUint8List();
  }

  /// Clean up old audio cache files, keeping only the most recent 5.
  void _cleanupAudioCache() {
    if (_audioCacheDir == null) return;
    try {
      final dir = Directory(_audioCacheDir!);
      if (!dir.existsSync()) return;
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.wav'))
          .toList();
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (files.length > 5) {
        for (final f in files.skip(5)) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Check if model needs downloading.
  Future<bool> needsDownload() async {
    if (_modelDir == null) await init();
    return !await _allModelFilesExist();
  }

  /// Get the model directory path.
  String? get modelDir => _modelDir;

  /// Get estimated model size on disk in MB.
  Future<double> getModelSizeMb() async {
    if (_modelDir == null) return 0;
    double totalBytes = 0;
    final dir = Directory(_modelDir!);
    if (!await dir.exists()) return 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        totalBytes += await entity.length();
      }
    }
    return totalBytes / (1024 * 1024);
  }

  /// Delete downloaded model files and free the engine.
  Future<void> deleteModel() async {
    // Stop playback and free engine
    await stop();
    _tts?.free();
    _tts = null;

    if (_modelDir != null) {
      final dir = Directory(_modelDir!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _isModelReady = false;
    }

    // Also clean audio cache
    if (_audioCacheDir != null) {
      final cacheDir = Directory(_audioCacheDir!);
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        await cacheDir.create(recursive: true);
      }
    }
  }

  /// Dispose and release all resources.
  void dispose() {
    _audioPlayer.dispose();
    _tts?.free();
    _tts = null;
  }
}
