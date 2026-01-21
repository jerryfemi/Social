import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:social/models/message_hive.dart';
import 'package:uuid/uuid.dart';

class HiveService {
  static final HiveService _instance = HiveService._internal();
  factory HiveService() => _instance;
  HiveService._internal();

  final _uuid = const Uuid();

  // track open boxes to avoid opening the same box multiple times
  final Map<String, Box<Message>> _openChatBoxes = {};
  Box<Map<dynamic, dynamic>>? _recentChatsBox;

  // INITIALIZATION
  Future<void> init() async {
    try {
      // open recents chat box
      _recentChatsBox = await Hive.openBox<Map>('recents_chats');
      debugPrint('✅ HiveService initialized');
    } catch (e) {
      debugPrint('❌ HiverService init error: $e');
      rethrow;
    }
  }

  // CHAT MESSAGES

  // get chat box for specific char room
  Future<Box<Message>> getChatBox(String chatRoomId) async {
    try {
      // return existing box if already open
      if (_openChatBoxes.containsKey(chatRoomId)) {
        return _openChatBoxes[chatRoomId]!;
      }

      // open new box
      final boxName = 'chat_$chatRoomId';
      final box = await Hive.openBox<Message>(boxName);
      _openChatBoxes[chatRoomId] = box;

      debugPrint('📦 Opened chat box: $chatRoomId (${box.length} messages)');
      return box;
    } catch (e) {
      debugPrint('❌ Error opening chat box $chatRoomId: $e');
      rethrow;
    }
  }

  // get all messages(for a chat)
  Future<List<Message>> getChatMessages(String chatRoomId) async {
    try {
      final box = await getChatBox(chatRoomId);
      final messages = box.values.toList();

      // sort by timestamp(oldest first)
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      debugPrint(
        '📨 Loaded ${messages.length} messages from Hive for $chatRoomId',
      );
      return messages;
    } catch (e) {
      debugPrint('❌ Error getting chat messages: $e');
      return [];
    }
  }

  // Add a new message to local storage (instant write)
  Future<Message> addMessage(String chatRoomId, Message message) async {
    try {
      final box = await getChatBox(chatRoomId);

      // Generate local ID if not provided
      final msg = message.localId.isEmpty
          ? message.copyWith(localId: _uuid.v4())
          : message;

      // Add to box
      await box.put(msg.localId, msg);

      debugPrint('💾 Saved message to Hive: ${msg.localId}');
      return msg;
    } catch (e) {
      debugPrint('❌ Error adding message: $e');
      rethrow;
    }
  }

  // update an existing message(for sync status and co.....)
  Future<void> updateMessage(Message message) async {
    try {
      if (message.isInBox) {
        await message.save();
        debugPrint('✏️ Updated message in Hive: ${message.localId}');
      } else {
        debugPrint('⚠️ Message not in box, cannot update: ${message.localId}');
      }
    } catch (e) {
      debugPrint('❌ Error updating message: $e');
      rethrow;
    }
  }

  //delete message
  Future<void> deleteMessage(Message message) async {
    try {
      if (message.isInBox) {
        await message.delete();
        debugPrint('🗑️ Deleted message from Hive: ${message.localId}');
      }
    } catch (e) {
      debugPrint('❌ Error deleting message: $e');
      rethrow;
    }
  }

  Future<Message?> findMessageByLocalId(
    String chatRoomId,
    String localId,
  ) async {
    try {
      final box = await getChatBox(chatRoomId);
      return box.values.firstWhere(
        (msg) => msg.localId == localId,
        orElse: () => throw StateError('Message not found'),
      );
    } catch (e) {
      return null;
    }
  }

  /// Find message by Firestore ID
  Future<Message?> findMessageByFirestoreId(
    String chatRoomId,
    String firestoreId,
  ) async {
    try {
      final box = await getChatBox(chatRoomId);
      return box.values.firstWhere(
        (msg) => msg.fireStoreId == firestoreId,
        orElse: () => throw StateError('Message not found'),
      );
    } catch (e) {
      return null;
    }
  }

  // Sync Firestore message to Hive (avoid duplicates)
  // In HiveService.dart

  Future<void> syncFirestoreMessage(
    String chatRoomId,
    bool isLocal,
    Map<String, dynamic> firestoreData,
    String firestoreId,
  ) async {
    try {
      final box = await getChatBox(chatRoomId);

      // 1. Get the localId that we just added to the map!
      final incomingLocalId = firestoreData['localId'] as String?;

      final newSyncStatus = isLocal
          ? MessageSyncStatus.pending
          : MessageSyncStatus.synced;

      // 2. Find the existing bubble using localId OR firestoreId
      final existing = box.values.firstWhere((msg) {
        final isLocalMatch =
            incomingLocalId != null && msg.localId == incomingLocalId;
        final isFirestoreMatch = msg.fireStoreId == firestoreId;
        return isLocalMatch || isFirestoreMatch;
      }, orElse: () => throw StateError('Not found'));

      if (existing.syncStatus != newSyncStatus ||
          existing.fireStoreId != firestoreId) {
        final updated = Message.fromFirestore(
          firestoreData,
          docId: firestoreId,
        );

        final merged = existing.copyWith(
          firestoreId: firestoreId,
          syncStatus: newSyncStatus,
          status: updated.status,
          timestamp: updated.timestamp,
        );

        // Put using the SAME key overwrites the old one
        await box.put(existing.localId, merged);
        debugPrint('✅ Merged local message: ${existing.localId}');
      }
    } catch (e) {
      if (e is StateError) {
        // Only add if it's TRULY new (from someone else)
        final newMsg = Message.fromFirestore(firestoreData, docId: firestoreId);
        final box = await getChatBox(chatRoomId);

        await box.put(newMsg.localId, newMsg);
        debugPrint('➕ Added new message from friend');
      }
    }
  }

  /// Trim old messages to save disk space (keep last 200 messages)
  Future<void> trimChatBox(String chatRoomId, {int keepLast = 200}) async {
    try {
      final box = await getChatBox(chatRoomId);

      if (box.length > keepLast) {
        final toDelete = box.length - keepLast;

        // Delete oldest messages
        for (int i = 0; i < toDelete; i++) {
          await box.deleteAt(0);
        }

        debugPrint('✂️ Trimmed $toDelete old messages from $chatRoomId');
      }
    } catch (e) {
      debugPrint('❌ Error trimming chat box: $e');
    }
  }

  /// Close a chat box (call when leaving chat screen)
  Future<void> closeChatBox(String chatRoomId) async {
    try {
      if (_openChatBoxes.containsKey(chatRoomId)) {
        await _openChatBoxes[chatRoomId]!.close();
        _openChatBoxes.remove(chatRoomId);
        debugPrint('📪 Closed chat box: $chatRoomId');
      }
    } catch (e) {
      debugPrint('❌ Error closing chat box: $e');
    }
  }

  // Update recent chat info (for home screen)
  Future<void> updateRecentChat({
    required String userId,
    required String username,
    required String? profileImage,
    required String lastMessage,
    required DateTime lastMessageTimestamp,
    required String lastMessageStatus,
    required String lastSenderId,
  }) async {
    try {
      await _recentChatsBox!.put(userId, {
        'uid': userId,
        'username': username,
        'profileImage': profileImage ?? '',
        'lastMessage': lastMessage,
        'lastMessageTimestamp': lastMessageTimestamp.millisecondsSinceEpoch,
        'lastMessageStatus': lastMessageStatus,
        'lastSenderId': lastSenderId,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      debugPrint('📝 Updated recent chat for $username');
    } catch (e) {
      debugPrint('❌ Error updating recent chat: $e');
    }
  }

  /// Get all recent chats (sorted by last message time)
  List<Map<String, dynamic>> getRecentChats() {
    try {
      final chats = _recentChatsBox!.values.map((item) {
        return Map<String, dynamic>.from(item);
      }).toList();

      // Sort by timestamp (newest first)
      chats.sort((a, b) {
        final aTime = a['lastMessageTimestamp'] as int? ?? 0;
        final bTime = b['lastMessageTimestamp'] as int? ?? 0;
        return bTime.compareTo(aTime);
      });

      debugPrint('📋 Loaded ${chats.length} recent chats from Hive');
      return chats;
    } catch (e) {
      debugPrint('❌ Error getting recent chats: $e');
      return [];
    }
  }

  /// Remove a chat from recent chats (when user blocks/deletes)
  Future<void> removeRecentChat(String userId) async {
    try {
      await _recentChatsBox!.delete(userId);
      debugPrint('🗑️ Removed recent chat for $userId');
    } catch (e) {
      debugPrint('❌ Error removing recent chat: $e');
    }
  }

  // ==================== CLEANUP ====================

  /// Clear all data for a specific chat
  Future<void> clearChat(String chatRoomId) async {
    try {
      final box = await getChatBox(chatRoomId);
      await box.clear();
      debugPrint('🧹 Cleared all messages for $chatRoomId');
    } catch (e) {
      debugPrint('❌ Error clearing chat: $e');
    }
  }

  /// Clear all Hive data (use for logout/reset)
  Future<void> clearAllData() async {
    try {
      // Close all open chat boxes
      for (final boxName in _openChatBoxes.keys.toList()) {
        await closeChatBox(boxName);
      }

      // Clear recent chats
      await _recentChatsBox?.clear();

      // Delete all boxes
      await Hive.deleteFromDisk();

      debugPrint('🧹 Cleared all Hive data');
    } catch (e) {
      debugPrint('❌ Error clearing all data: $e');
    }
  }

  // /// Get statistics (for debugging)
  // Future<Map<String, dynamic>> getStats() async {
  //   try {
  //     final stats = {
  //       'openChatBoxes': _openChatBoxes.length,
  //       'recentChatsCount': _recentChatsBox?.length ?? 0,
  //       'chatDetails': <String, int>{},
  //     };

  //     for (final entry in _openChatBoxes.entries) {
  //       stats['chatDetails'][entry.key] = entry.value.length;
  //     }

  //     return stats;
  //   } catch (e) {
  //     return {'error': e.toString()};
  //   }
  // }

  // ==================== LIFECYCLE ====================

  // ============ LOGOUT CLEANUP ============
  Future<void> clearOnLogout() async {
    try {
      if (_recentChatsBox == null || !_recentChatsBox!.isOpen) {
        _recentChatsBox = await Hive.openBox('recents_chats');
      }
      await _recentChatsBox!.clear();

      await Hive.close();

      debugPrint('🧹 Hive data cleared for logout');
    } catch (e) {
      debugPrint('⚠️ Error clearing Hive on logout: $e');
    }
  }

  /// Dispose (call on app termination)
  Future<void> dispose() async {
    try {
      // Close all chat boxes
      for (final box in _openChatBoxes.values) {
        await box.close();
      }
      _openChatBoxes.clear();

      // Close recent chats box
      await _recentChatsBox?.close();

      debugPrint('👋 HiveService disposed');
    } catch (e) {
      debugPrint('❌ Error disposing HiveService: $e');
    }
  }
}
