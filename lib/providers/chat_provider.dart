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

// TYPING STATUS PROVIDER
final typingStatusProvider = StreamProvider.family<bool, String>((
  ref,
  receiverId,
) {
  final chatService = ref.watch(chatServiceProvider);
  return chatService.getTypingStatus(receiverId);
});

//RECORDING STATUS PROVIDER
final recordingStatusProvider = StreamProvider.family<bool, String>((
  ref,
  receiverId,
) {
  final chatService = ref.watch(chatServiceProvider);
  return chatService.getRecordingStatus(receiverId);
});

// ONLINE STATUS PROVIDER
final onlineStatusProvider =
    StreamProvider.family<Map<String, dynamic>, String>((ref, userId) {
      final chatService = ref.watch(chatServiceProvider);
      return chatService.getUserOnlineStatus(userId);
    });
