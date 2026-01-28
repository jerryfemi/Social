import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive/hive.dart';
import 'package:social/models/message_hive.dart';
import 'package:social/providers/auth_provider.dart';
import 'package:social/providers/chat_provider.dart';
import 'package:social/providers/hive_service_provider.dart';
import 'package:social/services/chat_service.dart';
import 'package:social/services/hive_service.dart';
import 'package:uuid/uuid.dart';

final chatMessagesProvider =
    StateNotifierProvider.family<
      ChatMessagesNotifier,
      AsyncValue<List<Message>>,
      String
    >((ref, chatRoomId) {
      return ChatMessagesNotifier(chatRoomId: chatRoomId, ref: ref);
    });

class ChatMessagesNotifier extends StateNotifier<AsyncValue<List<Message>>> {
  final String chatRoomId;
  final Ref ref;

  late final ChatService _chatService;
  late final HiveService _hiveService;
  late final String _currentUserId;

  Box<Message>? _chatBox;
  StreamSubscription? _firestoreSubscription;
  StreamSubscription? _hiveSubscription;

  ChatMessagesNotifier({required this.chatRoomId, required this.ref})
    : super(const AsyncValue.loading()) {
    init();
  }

  Future<void> init() async {
    try {
      _hiveService = ref.read(hiveServiceProvider);
      _chatService = ref.read(chatServiceProvider);
      _currentUserId = ref.read(authServiceProvider).currentUser!.uid;

      // OPEN BOX
      _chatBox = await _hiveService.getChatBox(chatRoomId);

      // load from hive(immediately)
      final localMsg = await _hiveService.getChatMessages(chatRoomId);
      state = AsyncValue.data(localMsg);
      debugPrint('📱 Loaded ${localMsg.length} messages from Hive (instant)');

      // listen to hive box for changes
      _hiveSubscription = _chatBox!.watch().listen((event) {
        _updateStateFromHive();
      });

      // start firestore sync(in background)
      _startFirestoreSync();
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      debugPrint('❌ Error initializing chat: $e');
    }
  }

  // update state from hive
  Future<void> _updateStateFromHive() async {
    try {
      final messages = await _hiveService.getChatMessages(chatRoomId);

      // filter out messages deleted for current user
      final filteredMsg = messages
          .where((msg) => !msg.deletedFor.contains(_currentUserId))
          .toList();
      state = AsyncValue.data(filteredMsg);
    } catch (e) {
      debugPrint('❌ Error updating from Hive: $e');
    }
  }

  //start listning to firestore for sync
  void _startFirestoreSync() {
    _firestoreSubscription = FirebaseFirestore.instance
        .collection('Chat_rooms')
        .doc(chatRoomId)
        .collection('Messages')
        .orderBy('timestamp', descending: false)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshots) => _handleFirestoreUpdate(snapshots),
          onError: (e) => debugPrint('❌ Firestore sync error: $e'),
        );
  }

  // handle firestore update
  Future<void> _handleFirestoreUpdate(QuerySnapshot snapshot) async {
    try {
      for (final change in snapshot.docChanges) {
        final data = change.doc.data() as Map<String, dynamic>;
        final firestoreId = change.doc.id;

        // check if data is still on phone
        final bool isLocal = change.doc.metadata.hasPendingWrites;

        switch (change.type) {
          case DocumentChangeType.added:
            await _hiveService.syncFirestoreMessage(
              chatRoomId,
              isLocal,
              data,
              firestoreId,
            );
            break;
          case DocumentChangeType.modified:
            // update existing fields that may have changed
            final existing = await _hiveService.findMessageByFirestoreId(
              chatRoomId,
              firestoreId,
            );
            if (existing != null) {
              // update fields that may have changed
              final updated = Message.fromFirestore(data, docId: firestoreId);

              // preserve local fields
              final merged = updated.copyWith(
                localId: existing.localId,
                syncStatus: MessageSyncStatus.synced,
              );

              // replace in box
              await _chatBox!.put(existing.key, merged);
            } else {
              // New message from the cloud: add to Hive
              final newMsg = Message.fromFirestore(data, docId: firestoreId);
              await _chatBox!.put(newMsg.localId, newMsg);
            }
            break;
          case DocumentChangeType.removed:
            // remove from hive
            final existing = await _hiveService.findMessageByFirestoreId(
              chatRoomId,
              firestoreId,
            );
            if (existing != null) {
              await existing.delete();
            }
            break;
        }
      }
    } catch (e) {
      debugPrint('❌ Error handling Firestore update: $e');
    }
  }

  // send text message
  Future<void> sendTextMessage({
    required String receiverId,
    required String receiverName,
    required String text,
    String? replyToId,
    String? replyToMessage,
    String? replyToSender,
    String? replyToType,
    String type = 'text',
    String? caption,
  }) async {
    try {
      final currentUser = ref.read(authServiceProvider).currentUser!;

      // Get sender info
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(currentUser.uid)
          .get();
      final username = userDoc['username'] as String;

      // 1. Create message
      final message = Message(
        senderID: currentUser.uid,
        senderEmail: currentUser.email!,
        senderName: username,
        receiverID: receiverId,
        message: text,
        timestamp: DateTime.now(),
        type: type,
        caption: caption,
        status: MessageStatus.pending,
        localId: const Uuid().v4(),
        syncStatus: MessageSyncStatus.pending,
        replyToId: replyToId,
        replyToMessage: replyToMessage,
        replyToSender: replyToSender,
        replyToType: replyToType,
      );

      // 2. Save to Hive IMMEDIATELY (UI updates in ~1ms)
      await _hiveService.addMessage(chatRoomId, message);

      // 3. Update recent chats (for home screen)
      String lastMsg = text;
      if (type == 'image') {
        // Simple heuristic for generic images or GIFs
        lastMsg = caption ?? 'GIF';
      }

      await _hiveService.updateRecentChat(
        userId: receiverId,
        username: receiverName,
        profileImage: null,
        lastMessage: lastMsg,
        lastMessageTimestamp: message.timestamp,
        lastMessageStatus: 'pending',
        lastSenderId: currentUser.uid,
      );

      debugPrint('💾 Message saved to Hive, UI updated');

      // 4. Upload to Firestore in background
      _uploadTextMessageToFirestore(message, receiverId);
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      rethrow;
    }
  }

  /// Upload text message to Firestore (background)
  Future<void> _uploadTextMessageToFirestore(
    Message message,
    String receiverId,
  ) async {
    try {
      // Check if message was deleted before upload starts
      if (!message.isInBox) {
        debugPrint('🗑️ Message deleted locally, skipping upload');
        return;
      }

      // Mark as syncing
      message.syncStatus = MessageSyncStatus.syncing;
      await _hiveService.updateMessage(message);

      // Upload to Firestore using your existing ChatService
      await _chatService.sendMessage(
        receiverId,
        message.message,
        localId: message.localId,
        replyToId: message.replyToId,
        replyToMessage: message.replyToMessage,
        replyToSender: message.replyToSender,
        replyToType: message.replyToType,
        type: message.type,
        caption: message.caption,
      );

      // Note: We don't mark as synced here because Firestore listener will do it
      debugPrint('☁️ Message uploaded to Firestore');
    } catch (e) {
      // Mark as failed
      message.syncStatus = MessageSyncStatus.failed;

      debugPrint('❌ Failed to upload message to Firestore: $e');
    }
  }

  Future<void> sendMediaMessage({
    required String receiverId,
    required String receiverName,
    required String fileName,
    Uint8List? imageBytes,
    String? videoPath,
    String? imagePath,
    String? caption,
    String? replyToId,
    String? replyToMessage,
    String? replyToSender,
    String? replyToType,
  }) async {
    try {
      final currentUser = ref.read(authServiceProvider).currentUser!;

      // Get sender info
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(currentUser.uid)
          .get();
      final username = userDoc['username'] as String;

      final isVideo = videoPath != null;
      final type = isVideo ? 'video' : 'image';

      // 1. Create message with LOCAL file path
      final message = Message(
        senderID: currentUser.uid,
        senderEmail: currentUser.email!,
        senderName: username,
        receiverID: receiverId,
        message: '', // Will be Firebase URL after upload
        timestamp: DateTime.now(),
        type: type,
        caption: caption,
        status: 'pending',
        localId: const Uuid().v4(),
        syncStatus: MessageSyncStatus.pending,
        localFilePath: videoPath ?? imagePath, // Store local path
        replyToId: replyToId,
        replyToMessage: replyToMessage,
        replyToSender: replyToSender,
        replyToType: replyToType,
      );

      // 2. Save to Hive IMMEDIATELY with local path
      await _hiveService.addMessage(chatRoomId, message);

      // 3. Update recent chats
      final lastMsg = caption != null
          ? '${isVideo ? '🎥' : '📷'} $caption'
          : (isVideo ? '🎥 Video' : '📷 Photo');

      await _hiveService.updateRecentChat(
        userId: receiverId,
        username: receiverName,
        profileImage: null,
        lastMessage: lastMsg,
        lastMessageTimestamp: message.timestamp,
        lastMessageStatus: 'pending',
        lastSenderId: currentUser.uid,
      );

      debugPrint('💾 Media message saved to Hive with local path');

      // 4. Upload to Firebase Storage in background
      _uploadMediaToFirestore(
        message,
        receiverId,
        fileName,
        imageBytes: imageBytes,
        videoPath: videoPath,
      );
    } catch (e) {
      debugPrint('❌ Error sending media message: $e');
      rethrow;
    }
  }

  /// Upload media to Firebase Storage and Firestore (background)
  Future<void> _uploadMediaToFirestore(
    Message message,
    String receiverId,
    String fileName, {
    Uint8List? imageBytes,
    String? videoPath,
  }) async {
    try {
      // Check if message was deleted before upload starts
      if (!message.isInBox) {
        debugPrint('🗑️ Message deleted locally, skipping upload');
        return;
      }

      // Mark as syncing
      message.syncStatus = MessageSyncStatus.syncing;
      await _hiveService.updateMessage(message);

      // Use your existing ChatService to upload
      await _chatService.sendMediaMessage(
        receiverId,
        fileName,
        imageBytes: imageBytes,
        localId: message.localId,
        videoPath: videoPath,
        caption: message.caption,
        replyToId: message.replyToId,
        replyToMessage: message.replyToMessage,
        replyToSender: message.replyToSender,
        replyToType: message.replyToType,
      );

      debugPrint('☁️ Media uploaded to Firebase');

      // Firestore listener will update the message with URL and mark as synced
    } catch (e) {
      // Mark as failed
      message.syncStatus = MessageSyncStatus.failed;
      await _hiveService.updateMessage(message);

      debugPrint('❌ Failed to upload media to Firebase: $e');
    }
  }

  Future<void> sendVoiceMessage({
    required String receiverId,
    required String receiverName,
    required String localPath,
    required int duration,
    String? replyToId,
    String? replyToMessage,
    String? replyToSender,
    String? replyToType,
  }) async {
    try {
      final currentUser = ref.read(authServiceProvider).currentUser!;

      // Get sender info
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(currentUser.uid)
          .get();
      final username = userDoc['username'] as String;

      // 1. Create message with LOCAL file path
      final message = Message(
        senderID: currentUser.uid,
        senderEmail: currentUser.email!,
        senderName: username,
        receiverID: receiverId,
        message: '', // Will be Firebase URL after upload
        timestamp: DateTime.now(),
        type: 'voice',
        status: 'pending',
        voiceDuration: duration,
        localId: const Uuid().v4(),
        syncStatus: MessageSyncStatus.pending,
        localFilePath: localPath, // Store local path for immediate playback
        replyToId: replyToId,
        replyToMessage: replyToMessage,
        replyToSender: replyToSender,
        replyToType: replyToType,
      );

      // 2. Save to Hive IMMEDIATELY
      await _hiveService.addMessage(chatRoomId, message);

      // 3. Update recent chats
      await _hiveService.updateRecentChat(
        userId: receiverId,
        username: receiverName,
        profileImage: null,
        lastMessage: '🎤 Voice message',
        lastMessageTimestamp: message.timestamp,
        lastMessageStatus: 'pending',
        lastSenderId: currentUser.uid,
      );

      debugPrint('💾 Voice message saved to Hive with local path');

      // 4. Upload to Firebase Storage in background
      _uploadVoiceToFirestore(message, receiverId);
    } catch (e) {
      debugPrint('❌ Error sending voice message: $e');
      rethrow;
    }
  }

  /// Upload voice to Firebase Storage and Firestore (background)
  Future<void> _uploadVoiceToFirestore(
    Message message,
    String receiverId,
  ) async {
    try {
      // Check if message was deleted before upload starts
      if (!message.isInBox) {
        debugPrint('🗑️ Message deleted locally, skipping upload');
        return;
      }

      // Mark as syncing
      message.syncStatus = MessageSyncStatus.syncing;
      await _hiveService.updateMessage(message);

      // Use your existing ChatService to upload
      await _chatService.sendVoiceMessage(
        receiverId,
        message.localFilePath!,
        message.voiceDuration!,
        localId: message.localId,
        replyToId: message.replyToId,
        replyToMessage: message.replyToMessage,
        replyToSender: message.replyToSender,
        replyToType: message.replyToType,
      );

      debugPrint('☁️ Voice message uploaded to Firebase');

      // Firestore listener will update the message with URL and mark as synced
    } catch (e) {
      // Mark as failed
      message.syncStatus = MessageSyncStatus.failed;
      await _hiveService.updateMessage(message);

      debugPrint('❌ Failed to upload voice to Firebase: $e');
    }
  }

  /// Delete message
  Future<void> deleteMessage(
    String messageId, {
    bool deleteForEveryone = false,
  }) async {
    try {
      final message = await _hiveService.findMessageByLocalId(
        chatRoomId,
        messageId,
      );
      if (message == null) return;

      if (deleteForEveryone || message.senderID == _currentUserId) {
        // Delete from Hive
        await _hiveService.deleteMessage(message);

        // Delete from Firestore if synced
        if (message.fireStoreId != null) {
          final ids = chatRoomId.split('_');
          final otherUserId = ids.firstWhere((id) => id != _currentUserId);
          await _chatService.deleteMessage(
            otherUserId,
            message.fireStoreId!,
            deleteForEveryone: deleteForEveryone,
          );
        }
      } else {
        // Just hide for current user
        message.deletedFor.add(_currentUserId);
        await _hiveService.updateMessage(message);
      }
    } catch (e) {
      debugPrint('❌ Error deleting message: $e');
    }
  }

  /// Edit message
  Future<void> editMessage(String messageId, String newText) async {
    try {
      final message = await _hiveService.findMessageByLocalId(
        chatRoomId,
        messageId,
      );
      if (message == null || message.senderID != _currentUserId) return;

      // Update in Hive
      final edited = message.copyWith(
        message: newText,
        isEdited: true,
        editedAt: DateTime.now(),
      );

      await message.delete();
      await _chatBox!.add(edited);

      // Update in Firestore if synced
      if (message.fireStoreId != null) {
        final ids = chatRoomId.split('_');
        final otherUserId = ids.firstWhere((id) => id != _currentUserId);
        await _chatService.editMessage(
          otherUserId,
          message.fireStoreId!,
          newText,
        );
      }
    } catch (e) {
      debugPrint('❌ Error editing message: $e');
    }
  }

  @override
  void dispose() {
    _firestoreSubscription?.cancel();
    _hiveSubscription?.cancel();
    _hiveService.closeChatBox(chatRoomId);
    super.dispose();
  }
}
