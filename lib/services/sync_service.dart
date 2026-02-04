import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:social/models/message_hive.dart';
import 'package:social/services/chat_service.dart';
import 'package:social/services/hive_service.dart';

/// Service responsible for syncing failed/pending messages when connectivity is restored
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final HiveService _hiveService = HiveService();
  final ChatService _chatService = ChatService();
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isInitialized = false;
  bool _isSyncing = false;
  String? _currentUserId;

  // Track retry attempts per message to avoid infinite loops
  final Map<String, int> _retryAttempts = {};
  static const int _maxRetryAttempts = 3;

  /// Initialize the sync service with the current user ID
  Future<void> init(String userId) async {
    if (_isInitialized && _currentUserId == userId) return;

    _currentUserId = userId;
    _isInitialized = true;
    _retryAttempts.clear();

    // Cancel existing subscription
    await _connectivitySubscription?.cancel();

    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    debugPrint('🔄 SyncService initialized for user: $userId');

    // Check for pending messages on startup
    await _syncPendingMessages();
  }

  /// Handle connectivity changes
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasConnection = results.any((r) => r != ConnectivityResult.none);

    if (hasConnection) {
      debugPrint('🌐 Connection restored, checking for pending messages...');
      _syncPendingMessages();
    }
  }

  /// Scan all chat boxes for failed/pending messages and retry
  Future<void> _syncPendingMessages() async {
    if (_isSyncing || _currentUserId == null) return;

    _isSyncing = true;
    debugPrint('🔍 Scanning for failed/pending messages...');

    try {
      // Get all open chat box names from Hive
      final boxNames = await _getOpenChatBoxNames();

      int totalPending = 0;
      int totalFailed = 0;

      for (final boxName in boxNames) {
        final chatRoomId = boxName.replaceFirst('chat_', '');
        final messages = await _getFailedMessages(chatRoomId);

        for (final msg in messages) {
          if (msg.syncStatus == MessageSyncStatus.pending ||
              msg.syncStatus == MessageSyncStatus.syncing) {
            totalPending++;
          } else if (msg.syncStatus == MessageSyncStatus.failed) {
            totalFailed++;
          }

          // Retry the message
          await _retryMessage(chatRoomId, msg);
        }
      }

      debugPrint(
        '📊 Sync scan complete: $totalPending pending, $totalFailed failed',
      );
    } catch (e) {
      debugPrint('❌ Error during sync scan: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Get all chat box names from Hive
  Future<List<String>> _getOpenChatBoxNames() async {
    try {
      final boxes = <String>[];

      // Safely open recents box - it might not be open yet
      Box<Map> recentsBox;
      try {
        if (Hive.isBoxOpen('recents_chats_$_currentUserId')) {
          recentsBox = Hive.box<Map>('recents_chats_$_currentUserId');
        } else {
          recentsBox = await Hive.openBox<Map>('recents_chats_$_currentUserId');
        }
      } catch (e) {
        debugPrint('⚠️ Could not open recents box: $e');
        return [];
      }

      for (final entry in recentsBox.values) {
        final otherUserId = entry['userId'] as String?;
        if (otherUserId != null) {
          final ids = [_currentUserId!, otherUserId]..sort();
          final chatRoomId = ids.join('_');
          boxes.add('chat_$chatRoomId');
        }
      }

      return boxes;
    } catch (e) {
      debugPrint('❌ Error getting chat box names: $e');
      return [];
    }
  }

  /// Get failed/pending messages from a chat room
  Future<List<Message>> _getFailedMessages(String chatRoomId) async {
    try {
      final messages = await _hiveService.getChatMessages(chatRoomId);
      return messages.where((msg) {
        return msg.senderID == _currentUserId &&
            (msg.syncStatus == MessageSyncStatus.failed ||
                msg.syncStatus == MessageSyncStatus.pending ||
                msg.syncStatus == MessageSyncStatus.syncing);
      }).toList();
    } catch (e) {
      debugPrint('❌ Error getting failed messages for $chatRoomId: $e');
      return [];
    }
  }

  /// Retry uploading a single message
  Future<bool> _retryMessage(String chatRoomId, Message message) async {
    // Check retry attempts
    final attempts = _retryAttempts[message.localId] ?? 0;
    if (attempts >= _maxRetryAttempts) {
      debugPrint(
        '⚠️ Max retry attempts reached for ${message.localId}, skipping',
      );
      return false;
    }

    _retryAttempts[message.localId] = attempts + 1;

    // Add delay before retry (exponential backoff: 2s, 4s, 6s)
    final delaySeconds = 2 * (attempts + 1);
    debugPrint(
      '⏳ Waiting ${delaySeconds}s before retry attempt ${attempts + 1}...',
    );
    await Future.delayed(Duration(seconds: delaySeconds));

    try {
      debugPrint(
        '🔄 Retrying message ${message.localId} (attempt ${attempts + 1})',
      );

      // Mark as syncing
      message.syncStatus = MessageSyncStatus.syncing;
      await _hiveService.updateMessage(message);

      // Retry based on message type
      switch (message.type) {
        case 'text':
        case 'image' when message.message.startsWith('http'):
          // GIF or already uploaded image - just send to Firestore
          await _retrySendToFirestore(message);
          break;

        case 'image':
        case 'video':
          await _retryMediaUpload(message);
          break;

        case 'voice':
          await _retryVoiceUpload(message);
          break;

        default:
          await _retrySendToFirestore(message);
      }

      // Clear retry count on success
      _retryAttempts.remove(message.localId);
      debugPrint('✅ Message ${message.localId} synced successfully');
      return true;
    } catch (e) {
      // Mark as failed again
      message.syncStatus = MessageSyncStatus.failed;
      await _hiveService.updateMessage(message);

      debugPrint('❌ Retry failed for ${message.localId}: $e');
      return false;
    }
  }

  /// Retry sending a text/GIF message to Firestore
  Future<void> _retrySendToFirestore(Message message) async {
    await _chatService.sendMessage(
      message.receiverID,
      message.message,
      localId: message.localId,
      replyToId: message.replyToId,
      replyToMessage: message.replyToMessage,
      replyToSender: message.replyToSender,
      replyToType: message.replyToType,
      type: message.type,
      caption: message.caption,
    );
  }

  /// Retry uploading media (image/video)
  Future<void> _retryMediaUpload(Message message) async {
    // Check if we have local file path
    if (message.localFilePath == null || message.localFilePath!.isEmpty) {
      // No local file, check if message URL exists (already uploaded)
      if (message.message.startsWith('http')) {
        await _retrySendToFirestore(message);
        return;
      }
      throw Exception('No local file path for media message');
    }

    // Check if file still exists
    final file = File(message.localFilePath!);
    if (!await file.exists()) {
      throw Exception('Local file no longer exists: ${message.localFilePath}');
    }

    // Read file bytes and upload
    final bytes = await file.readAsBytes();
    final fileName = message.localFilePath!.split('/').last;

    await _chatService.sendMediaMessage(
      message.receiverID,
      fileName,
      imageBytes: message.type == 'image' ? bytes : null,
      videoPath: message.type == 'video' ? message.localFilePath : null,
      localId: message.localId,
      caption: message.caption,
      replyToId: message.replyToId,
      replyToMessage: message.replyToMessage,
      replyToSender: message.replyToSender,
      replyToType: message.replyToType,
    );
  }

  /// Retry uploading voice message
  Future<void> _retryVoiceUpload(Message message) async {
    if (message.localFilePath == null || message.localFilePath!.isEmpty) {
      // Check if already uploaded
      if (message.message.startsWith('http')) {
        await _retrySendToFirestore(message);
        return;
      }
      throw Exception('No local file path for voice message');
    }

    // Check if file still exists
    final file = File(message.localFilePath!);
    if (!await file.exists()) {
      throw Exception('Voice file no longer exists: ${message.localFilePath}');
    }

    await _chatService.sendVoiceMessage(
      message.receiverID,
      message.localFilePath!,
      message.voiceDuration ?? 0,
      localId: message.localId,
      replyToId: message.replyToId,
      replyToMessage: message.replyToMessage,
      replyToSender: message.replyToSender,
      replyToType: message.replyToType,
    );
  }

  /// Public method to manually retry a specific message
  Future<bool> retryMessageById(String chatRoomId, String localId) async {
    try {
      final message = await _hiveService.findMessageByLocalId(
        chatRoomId,
        localId,
      );
      if (message == null) {
        debugPrint('❌ Message not found: $localId');
        return false;
      }

      // Reset retry count for manual retry
      _retryAttempts.remove(localId);

      return await _retryMessage(chatRoomId, message);
    } catch (e) {
      debugPrint('❌ Error retrying message $localId: $e');
      return false;
    }
  }

  /// Public method to retry all failed messages
  Future<void> retryAllFailed() async {
    // Reset all retry counts
    _retryAttempts.clear();
    await _syncPendingMessages();
  }

  /// Get count of failed messages for current user
  Future<int> getFailedMessageCount() async {
    if (_currentUserId == null) return 0;

    try {
      final boxNames = await _getOpenChatBoxNames();
      int count = 0;

      for (final boxName in boxNames) {
        final chatRoomId = boxName.replaceFirst('chat_', '');
        final messages = await _getFailedMessages(chatRoomId);
        count += messages
            .where((m) => m.syncStatus == MessageSyncStatus.failed)
            .length;
      }

      return count;
    } catch (e) {
      return 0;
    }
  }

  /// Cleanup on logout
  void dispose() {
    _connectivitySubscription?.cancel();
    _isInitialized = false;
    _currentUserId = null;
    _retryAttempts.clear();
    debugPrint('🧹 SyncService disposed');
  }
}
