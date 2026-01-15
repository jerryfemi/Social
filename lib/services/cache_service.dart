import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to cache data locally for instant loading
class CacheService {
  static const String _recentChatsKey = 'cached_recent_chats';
  static const String _recentChatsTimestampKey =
      'cached_recent_chats_timestamp';
  static const String _chatMessagesKeyPrefix = 'cached_messages_';
  static const String _chatMessagesTimestampPrefix = 'cached_messages_ts_';

  /// Save recent chats to local cache
  static Future<void> cacheRecentChats(List<Map<String, dynamic>> chats) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Convert to JSON-safe format (handle Timestamp objects)
      final jsonSafeChats = chats.map((chat) {
        final safeChatMap = <String, dynamic>{};
        chat.forEach((key, value) {
          if (value is DateTime) {
            safeChatMap[key] = value.millisecondsSinceEpoch;
          } else if (value != null &&
              value.runtimeType.toString().contains('Timestamp')) {
            // Handle Firestore Timestamp
            safeChatMap[key] = (value as dynamic).millisecondsSinceEpoch;
          } else {
            safeChatMap[key] = value;
          }
        });
        return safeChatMap;
      }).toList();

      await prefs.setString(_recentChatsKey, jsonEncode(jsonSafeChats));
      await prefs.setInt(
        _recentChatsTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      debugPrint('CacheService: Cached ${chats.length} recent chats');
    } catch (e) {
      debugPrint('CacheService: Error caching recent chats: $e');
    }
  }

  /// Get cached recent chats (returns null if no cache or expired)
  static Future<List<Map<String, dynamic>>?> getCachedRecentChats({
    Duration maxAge = const Duration(days: 7),
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final timestampMs = prefs.getInt(_recentChatsTimestampKey);
      if (timestampMs == null) return null;

      // Check if cache is expired
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestampMs);
      if (DateTime.now().difference(cacheTime) > maxAge) {
        debugPrint('CacheService: Cache expired');
        return null;
      }

      final jsonString = prefs.getString(_recentChatsKey);
      if (jsonString == null) return null;

      final List<dynamic> decoded = jsonDecode(jsonString);
      final chats = decoded.map((item) {
        final map = Map<String, dynamic>.from(item);
        // Convert timestamp back to int for display
        if (map['lastMessageTimestamp'] is int) {
          // Keep as int - the UI will handle it
        }
        return map;
      }).toList();

      debugPrint('CacheService: Loaded ${chats.length} cached chats');
      return chats;
    } catch (e) {
      debugPrint('CacheService: Error loading cached chats: $e');
      return null;
    }
  }

  // ======================== CHAT MESSAGES CACHING ========================

  /// Generate chat room ID from two user IDs
  static String _getChatRoomId(String currentUserId, String otherUserId) {
    final ids = [currentUserId, otherUserId]..sort();
    return ids.join('_');
  }

  /// Save chat messages to local cache
  static Future<void> cacheChatMessages(
    String currentUserId,
    String otherUserId,
    List<Map<String, dynamic>> messages,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chatRoomId = _getChatRoomId(currentUserId, otherUserId);

      // Convert to JSON-safe format (handle Timestamp objects)
      final jsonSafeMessages = messages.map((msg) {
        final safeMap = <String, dynamic>{};
        msg.forEach((key, value) {
          if (value is DateTime) {
            safeMap[key] = value.millisecondsSinceEpoch;
          } else if (value != null &&
              value.runtimeType.toString().contains('Timestamp')) {
            // Handle Firestore Timestamp
            safeMap[key] = (value as dynamic).millisecondsSinceEpoch;
          } else {
            safeMap[key] = value;
          }
        });
        return safeMap;
      }).toList();

      // Only cache last 50 messages to save storage
      final messagesToCache = jsonSafeMessages.length > 50
          ? jsonSafeMessages.sublist(jsonSafeMessages.length - 50)
          : jsonSafeMessages;

      await prefs.setString(
        '$_chatMessagesKeyPrefix$chatRoomId',
        jsonEncode(messagesToCache),
      );
      await prefs.setInt(
        '$_chatMessagesTimestampPrefix$chatRoomId',
        DateTime.now().millisecondsSinceEpoch,
      );
      debugPrint(
        'CacheService: Cached ${messagesToCache.length} messages for $chatRoomId',
      );
    } catch (e) {
      debugPrint('CacheService: Error caching messages: $e');
    }
  }

  /// Get cached chat messages
  static Future<List<Map<String, dynamic>>?> getCachedChatMessages(
    String currentUserId,
    String otherUserId, {
    Duration maxAge = const Duration(days: 7),
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chatRoomId = _getChatRoomId(currentUserId, otherUserId);

      final timestampMs = prefs.getInt(
        '$_chatMessagesTimestampPrefix$chatRoomId',
      );
      if (timestampMs == null) return null;

      // Check if cache is expired
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestampMs);
      if (DateTime.now().difference(cacheTime) > maxAge) {
        debugPrint('CacheService: Messages cache expired for $chatRoomId');
        return null;
      }

      final jsonString = prefs.getString('$_chatMessagesKeyPrefix$chatRoomId');
      if (jsonString == null) return null;

      final List<dynamic> decoded = jsonDecode(jsonString);
      final messages = decoded.map((item) {
        return Map<String, dynamic>.from(item);
      }).toList();

      debugPrint(
        'CacheService: Loaded ${messages.length} cached messages for $chatRoomId',
      );
      return messages;
    } catch (e) {
      debugPrint('CacheService: Error loading cached messages: $e');
      return null;
    }
  }

  /// Clear cached messages for a specific chat
  static Future<void> clearChatCache(
    String currentUserId,
    String otherUserId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chatRoomId = _getChatRoomId(currentUserId, otherUserId);
      await prefs.remove('$_chatMessagesKeyPrefix$chatRoomId');
      await prefs.remove('$_chatMessagesTimestampPrefix$chatRoomId');
      debugPrint('CacheService: Cleared cache for $chatRoomId');
    } catch (e) {
      debugPrint('CacheService: Error clearing chat cache: $e');
    }
  }

  // ======================== GENERAL ========================

  /// Clear all cached data
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentChatsKey);
      await prefs.remove(_recentChatsTimestampKey);
      // Note: This doesn't clear individual chat caches
      // They will expire naturally or can be cleared with clearChatCache
      debugPrint('CacheService: Cache cleared');
    } catch (e) {
      debugPrint('CacheService: Error clearing cache: $e');
    }
  }
}
