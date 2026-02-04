import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for playing in-app sounds (send, receive, notification)
/// Sounds are downloaded from Firebase Storage and cached locally.
/// Auto-updates when remote file changes (checks Last-Modified header).
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final AudioPlayer _sendPlayer = AudioPlayer();
  final AudioPlayer _receivePlayer = AudioPlayer();
  final AudioPlayer _notificationPlayer = AudioPlayer();

  bool _isInitialized = false;
  bool _soundsEnabled = true;

  // Local cache directory path
  String? _soundsDir;

  // ============================================================
  // REMOTE SOUND URLs (Firebase Storage)
  // Upload your mp3 files to: Firebase Console > Storage > sounds/
  // ============================================================
  static const String _storageBucket = 'social-960eb.firebasestorage.app';
  static const Map<String, String> _soundUrls = {
    'send':
        'https://firebasestorage.googleapis.com/v0/b/$_storageBucket/o/sounds%2Fsend.mp3?alt=media',
    'receive':
        'https://firebasestorage.googleapis.com/v0/b/$_storageBucket/o/sounds%2Freceive.mp3?alt=media',
    'notification':
        'https://firebasestorage.googleapis.com/v0/b/$_storageBucket/o/sounds%2Fnotification.mp3?alt=media',
  };

  // ============================================================
  // OLD CODE - Asset paths (commented out for reference)
  // ============================================================
  // static const String _sendSound = 'sounds/receive.mp3';
  // static const String _receiveSound = 'sounds/notification.mp3';
  // static const String _notificationSound = 'sounds/send.mp3';

  /// Enable or disable sounds globally
  set soundsEnabled(bool value) => _soundsEnabled = value;
  bool get soundsEnabled => _soundsEnabled;

  /// Initialize audio players and download/cache sounds
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      // Set release mode for short sounds
      await _sendPlayer.setReleaseMode(ReleaseMode.stop);
      await _receivePlayer.setReleaseMode(ReleaseMode.stop);
      await _notificationPlayer.setReleaseMode(ReleaseMode.stop);

      // Setup local cache directory
      final dir = await getApplicationDocumentsDirectory();
      _soundsDir = '${dir.path}/sounds';
      await Directory(_soundsDir!).create(recursive: true);

      // Download/update sounds in background (don't block init)
      _syncSoundsFromRemote();

      debugPrint('🔊 SoundService initialized');
    } catch (e) {
      debugPrint('⚠️ SoundService init error: $e');
    }
  }

  /// Sync sounds from Firebase Storage (download new or updated files)
  Future<void> _syncSoundsFromRemote() async {
    // Skip on web - use assets instead
    if (kIsWeb) return;

    final prefs = await SharedPreferences.getInstance();

    for (final entry in _soundUrls.entries) {
      final name = entry.key;
      final url = entry.value;
      final localFile = File('$_soundsDir/$name.mp3');

      try {
        // Check remote file's Last-Modified
        final headResponse = await http
            .head(Uri.parse(url))
            .timeout(const Duration(seconds: 5));

        final remoteLastModified = headResponse.headers['last-modified'] ?? '';
        final cachedLastModified =
            prefs.getString('sound_${name}_modified') ?? '';

        // Download if: file doesn't exist OR remote is newer
        if (!await localFile.exists() ||
            remoteLastModified != cachedLastModified) {
          debugPrint('🔊 Downloading $name.mp3...');

          final response = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 15));

          if (response.statusCode == 200) {
            await localFile.writeAsBytes(response.bodyBytes);
            await prefs.setString('sound_${name}_modified', remoteLastModified);
            debugPrint('🔊 Downloaded $name.mp3 ✓');
          }
        } else {
          debugPrint('🔊 $name.mp3 is up to date');
        }
      } catch (e) {
        debugPrint('🔊 Failed to sync $name.mp3: $e');
        // Will use cached version or fallback to asset
      }
    }
  }

  /// Get the audio source for a sound (local cache → asset fallback)
  Future<Source> _getSource(String name) async {
    // On web, always use assets
    if (kIsWeb) {
      return AssetSource('sounds/$name.mp3');
    }

    final localFile = File('$_soundsDir/$name.mp3');
    if (await localFile.exists()) {
      return DeviceFileSource(localFile.path);
    }

    // Fallback to bundled asset if not downloaded yet
    return AssetSource('sounds/$name.mp3');
  }

  /// Play sound when sending a message
  Future<void> playSend() async {
    if (!_soundsEnabled) return;

    // Check connectivity - don't play if offline
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) return;

    try {
      await _sendPlayer.stop();
      final source = await _getSource('send');
      await _sendPlayer.play(source);
    } catch (e) {
      debugPrint('🔊 playSend error: $e');
    }

    // ============================================================
    // OLD CODE (commented out for reference)
    // ============================================================
    // try {
    //   await _sendPlayer.stop();
    //   await _sendPlayer.play(AssetSource(_sendSound));
    // } catch (e) {
    //   debugPrint('🔊 playSend error: $e');
    // }
  }

  /// Play sound when receiving a message (in-chat)
  Future<void> playReceive() async {
    if (!_soundsEnabled) return;
    try {
      await _receivePlayer.stop();
      final source = await _getSource('receive');
      await _receivePlayer.play(source);
    } catch (e) {
      debugPrint('🔊 playReceive error: $e');
    }

    // ============================================================
    // OLD CODE (commented out for reference)
    // ============================================================
    // try {
    //   await _receivePlayer.stop();
    //   await _receivePlayer.play(AssetSource(_receiveSound));
    // } catch (e) {
    //   debugPrint('🔊 playReceive error: $e');
    // }
  }

  /// Play sound for notifications (home screen / background)
  Future<void> playNotification() async {
    if (!_soundsEnabled) return;
    try {
      await _notificationPlayer.stop();
      final source = await _getSource('notification');
      await _notificationPlayer.play(source);
    } catch (e) {
      debugPrint('🔊 playNotification error: $e');
    }

    // ============================================================
    // OLD CODE (commented out for reference)
    // ============================================================
    // try {
    //   await _notificationPlayer.stop();
    //   await _notificationPlayer.play(AssetSource(_notificationSound));
    // } catch (e) {
    //   debugPrint('🔊 playNotification error: $e');
    // }
  }

  /// Dispose players when app closes
  void dispose() {
    _sendPlayer.dispose();
    _receivePlayer.dispose();
    _notificationPlayer.dispose();
  }
}
