import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:social/providers/auth_provider.dart';
import 'package:social/services/chat_service.dart';

final chatServiceProvider = ChangeNotifierProvider<ChatService>((ref) {
  return ChatService();
});

final userProfileProvider = StreamProvider.family<DocumentSnapshot, String>((
  ref,
  id,
) {
  final chatService = ref.watch(chatServiceProvider);
  return chatService.getUserStream(id);
});

// 2. SEARCH
final searchUsersProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, query) {
      final chatService = ref.watch(chatServiceProvider);
      return chatService.searchUsers(query);
    });

// CHAT MESSAGE PROVIDER
final messageProvider = StreamProvider.family<QuerySnapshot, String>((
  ref,
  receiverID,
) {
  final chatService = ref.watch(chatServiceProvider);
  final currentUser = ref.watch(authServiceProvider).currentUser!;

  return chatService.getMessages(currentUser.uid, receiverID);
});

// CHAT STREAM PROVIDER
final chatStreamProvider = StreamProvider.family<DocumentSnapshot, String>((
  ref,
  receiverId,
) {
  final chatService = ref.watch(chatServiceProvider);
  return chatService.getChatStream(receiverId);
});

// BLOCKED USERS PROVIDER
final blockedUsersProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, userId) {
      final chatService = ref.watch(chatServiceProvider);
      return chatService.getblockedUsers(userId);
    });

// CONNECTIVITY PROVIDER
final connectivityProvider =
    StreamProvider.autoDispose<List<ConnectivityResult>>((ref) {
      return Connectivity().onConnectivityChanged;
    });

// STARRED MESSAGES PROVIDER
final starredMessagesProvider = StreamProvider<QuerySnapshot>((ref) {
  final chatService = ref.watch(chatServiceProvider);
  return chatService.getStarredMessages();
});

// TYPING STATUS PROVIDER (1-on-1)
final typingStatusProvider = StreamProvider.family<bool, String>((
  ref,
  receiverId,
) {
  final chatService = ref.watch(chatServiceProvider);
  return chatService.getTypingStatus(receiverId);
});

// GROUP TYPING PROVIDER
final groupTypingStatusProvider =
    StreamProvider.family<Map<String, dynamic>, String>((ref, groupId) {
      final chatService = ref.watch(chatServiceProvider);
      return chatService.getGroupTypingStatus(groupId);
    });

//RECORDING STATUS PROVIDER (1-on-1)
final recordingStatusProvider = StreamProvider.family<bool, String>((
  ref,
  receiverId,
) {
  final chatService = ref.watch(chatServiceProvider);
  return chatService.getRecordingStatus(receiverId);
});

// GROUP RECORDING PROVIDER
final groupRecordingStatusProvider =
    StreamProvider.family<Map<String, dynamic>, String>((ref, groupId) {
      final chatService = ref.watch(chatServiceProvider);
      return chatService.getGroupRecordingStatus(groupId);
    });

// ONLINE STATUS PROVIDER
final onlineStatusProvider =
    StreamProvider.family<Map<String, dynamic>, String>((ref, userId) {
      final chatService = ref.watch(chatServiceProvider);
      return chatService.getUserOnlineStatus(userId);
    });
// 8. FULL MEDIA PROVIDERS (Cached for Media Screens)
final chatMediaProvider =
    StreamProvider.family<List<QueryDocumentSnapshot>, String>((
      ref,
      chatRoomId,
    ) {
      return FirebaseFirestore.instance
          .collection('Chat_rooms')
          .doc(chatRoomId)
          .collection('Messages')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .map((snapshot) {
            return snapshot.docs.where((doc) {
              final type = doc.data()['type'] as String?;
              return type == 'image' || type == 'video';
            }).toList();
          });
    });

final groupMediaProvider =
    StreamProvider.family<List<QueryDocumentSnapshot>, String>((ref, groupId) {
      return FirebaseFirestore.instance
          .collection('Chat_rooms')
          .doc(groupId)
          .collection('Messages')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .map((snapshot) {
            return snapshot.docs.where((doc) {
              final type = doc.data()['type'] as String?;
              return type == 'image' || type == 'video';
            }).toList();
          });
    });

/// Provider to get group info from Firestore
final groupInfoProvider = StreamProvider.family<DocumentSnapshot, String>((
  ref,
  groupId,
) {
  return FirebaseFirestore.instance
      .collection('Chat_rooms')
      .doc(groupId)
      .snapshots();
});
