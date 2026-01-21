import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Singleton AudioService to prevent multiple instances and OOM errors
class AudioService {
  // Singleton instance
  static final AudioService _instance = AudioService._internal();

  // Factory constructor returns the singleton
  factory AudioService() => _instance;

  // Private constructor
  AudioService._internal() {
    // FIX: Listeners initialized ONCE here to prevent memory leaks
    player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _currentlyPlayingUrl = null;
      debugPrint('Global Player: Playback complete');
    });

    player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
    });
  }
  // Lazy initialization of recorder and player
  AudioRecorder? _recorder;
  AudioPlayer? _player;

  AudioRecorder get recorder {
    _recorder ??= AudioRecorder();
    return _recorder!;
  }

  AudioPlayer get player {
    _player ??= AudioPlayer();
    return _player!;
  }

  bool _isRecording = false;
  bool _isPlaying = false;
  String? _currentlyPlayingUrl;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;

  // Getters
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  String? get currentlyPlayingUrl => _currentlyPlayingUrl;
  Duration get recordingDuration => _recordingDuration;

  // Stream for playback position
  Stream<Duration> get positionStream => player.onPositionChanged;
  Stream<Duration> get durationStream => player.onDurationChanged;
  Stream<PlayerState> get playerStateStream => player.onPlayerStateChanged;

  // Safely stop the recording timer
  void _stopTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  // Check if we have microphone permission
  Future<bool> hasPermission() async {
    return await recorder.hasPermission();
  }

  // Start recording audio
  Future<String?> startRecording() async {
    try {
      // Stop any existing timer first
      _stopTimer();

      if (!await hasPermission()) {
        debugPrint('Microphone permission denied');
        return null;
      }

      // Get temp directory for storing recording
      final Directory tempDir = await getTemporaryDirectory();
      final String filePath =
          '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Configure recording
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      );

      await recorder.start(config, path: filePath);
      _isRecording = true;
      _recordingDuration = Duration.zero;

      // Start timer to track duration
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _recordingDuration += const Duration(seconds: 1);
      });

      debugPrint('Recording started: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('Error starting recording: $e');
      return null;
    }
  }

  // Stop recording and return the file path and duration
  Future<({String? path, int duration})?> stopRecording() async {
    try {
      if (!_isRecording) return null;

      _stopTimer();

      final String? path = await recorder.stop();
      final int duration = _recordingDuration.inSeconds;

      _isRecording = false;
      _recordingDuration = Duration.zero;

      debugPrint('Recording stopped: $path (${duration}s)');
      return (path: path, duration: duration);
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Cancel recording without saving
  Future<void> cancelRecording() async {
    try {
      _stopTimer();

      if (_isRecording) {
        final path = await recorder.stop();
        // Delete the file
        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }

      _isRecording = false;
      _recordingDuration = Duration.zero;
      debugPrint('Recording cancelled');
    } catch (e) {
      debugPrint('Error cancelling recording: $e');
    }
  }

  /// Play audio from URL (with caching for offline playback)
  Future<void> play(String url) async {
    try {
      // If same audio is playing, pause it
      if (_isPlaying && _currentlyPlayingUrl == url) {
        await pause();
        return;
      }

      // If different audio, stop current and play new
      if (_currentlyPlayingUrl != url) {
        await stop();
      }

      // Try to get cached file, download if not cached
      File? cachedFile;
      try {
        final fileInfo = await DefaultCacheManager().getFileFromCache(url);
        if (fileInfo != null) {
          cachedFile = fileInfo.file;
          debugPrint('Playing from cache: ${cachedFile.path}');
        } else {
          // Download and cache the file
          cachedFile = await DefaultCacheManager().getSingleFile(url);
          debugPrint('Downloaded and cached: ${cachedFile.path}');
        }
      } catch (e) {
        // If caching fails (e.g., no internet and not cached), try URL source
        debugPrint('Cache failed, trying URL source: $e');
      }

      // Play from cached file if available, otherwise try URL
      if (cachedFile != null && await cachedFile.exists()) {
        await player.play(DeviceFileSource(cachedFile.path));
      } else {
        await player.play(UrlSource(url));
      }

      _isPlaying = true;
      _currentlyPlayingUrl = url;
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

/// Play audio from local file OR URL
Future<void> playSource(String source, {bool isLocal = false}) async {
  try {
    // If same audio is playing, pause it
    if (_isPlaying && _currentlyPlayingUrl == source) {
      await pause();
      return;
    }

    // If different audio, stop current and play new
    if (_currentlyPlayingUrl != source) {
      await stop();
    }

    if (isLocal) {
      // Play from local file
      debugPrint('Playing from local file: $source');
      await player.play(DeviceFileSource(source));
    } else {
      // Play from URL (with caching)
      File? cachedFile;
      try {
        final fileInfo = await DefaultCacheManager().getFileFromCache(source);
        if (fileInfo != null) {
          cachedFile = fileInfo.file;
          debugPrint('Playing from cache: ${cachedFile.path}');
        } else {
          cachedFile = await DefaultCacheManager().getSingleFile(source);
          debugPrint('Downloaded and cached: ${cachedFile.path}');
        }
      } catch (e) {
        debugPrint('Cache failed, trying URL source: $e');
      }

      if (cachedFile != null && await cachedFile.exists()) {
        await player.play(DeviceFileSource(cachedFile.path));
      } else {
        await player.play(UrlSource(source));
      }
    }

    _isPlaying = true;
    _currentlyPlayingUrl = source;
  } catch (e) {
    debugPrint('Error playing audio: $e');
  }
}

  /// Pause playback
  Future<void> pause() async {
    try {
      await player.pause();
      _isPlaying = false;
    } catch (e) {
      debugPrint('Error pausing audio: $e');
    }
  }

  /// Resume playback
  Future<void> resume() async {
    try {
      await player.resume();
      _isPlaying = true;
    } catch (e) {
      debugPrint('Error resuming audio: $e');
    }
  }

  /// Stop playback
  Future<void> stop() async {
    try {
      await player.stop();
      _isPlaying = false;
      _currentlyPlayingUrl = null;
    } catch (e) {
      debugPrint('Error stopping audio: $e');
    }
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    try {
      await player.seek(position);
    } catch (e) {
      debugPrint('Error seeking: $e');
    }
  }

  /// Check if specific URL is currently playing
  bool isPlayingUrl(String url) {
    return _isPlaying && _currentlyPlayingUrl == url;
  }

  /// Format duration to mm:ss
  static String formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  // Dispose resources - Note: For singleton, only call on app termination
  void dispose() {
    _stopTimer();
    _recorder?.dispose();
    _player?.dispose();
    _recorder = null;
    _player = null;
  }
}
