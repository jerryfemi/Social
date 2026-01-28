import 'dart:async';
import 'dart:core';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:social/providers/auth_provider.dart';
import 'package:social/providers/hive_service_provider.dart';
import 'package:social/services/hive_service.dart';

// Provider for recent chats (Local-First)

final recentChatsProvider =
    StateNotifierProvider<RecentChatsNotifier, List<Map<String, dynamic>>>((
      ref,
    ) {
      // Watch for auth changes to force rebuild on logout/login
      ref.watch(authStateProvider);
      return RecentChatsNotifier(ref: ref);
    });

class RecentChatsNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  final Ref ref;
  late final HiveService _hiveService;
  late final String _currentUserId;
  StreamSubscription? _firestoreSubscription;

  RecentChatsNotifier({required this.ref}) : super([]) {
    _init();
  }

  Future<void> _init() async {
    try {
      _hiveService = ref.read(hiveServiceProvider);

      final authService = ref.read(authServiceProvider);
      if (authService.currentUser == null) {
        state = [];
        return;
      }

      _currentUserId = authService.currentUser!.uid;

      // 1. Initialize user-specific box
      await _hiveService.initRecentsForUser(_currentUserId);

      // 2. Load from Hive
      state = _hiveService.getRecentChats();
      debugPrint('📱 Loaded ${state.length} recent chats from Hive (instant)');

      // 3. Start Firestore sync in background
      _startFirestoreSync();
    } catch (e) {
      debugPrint('❌ Error initializing recent chats: $e');
    }
  }

  void _startFirestoreSync() {
    _firestoreSubscription = FirebaseFirestore.instance
        .collection('Chat_rooms')
        .where('participants', arrayContains: _currentUserId)
        .snapshots()
        .listen((snapshot) async {
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final participants = List<String>.from(data['participants']);

            final otherUserId = participants.firstWhere(
              (id) => id != _currentUserId,
              orElse: () => '',
            );

            if (otherUserId.isEmpty) continue;

            // Get user info
            final userDoc = await FirebaseFirestore.instance
                .collection('Users')
                .doc(otherUserId)
                .get();

            if (!userDoc.exists) continue;

            final userData = userDoc.data()!;

            // Update Hive
            await _hiveService.updateRecentChat(
              userId: otherUserId,
              username: userData['username'],
              profileImage: userData['profileImage'],
              lastMessage: data['lastMessage'] ?? '',
              lastMessageTimestamp: (data['lastMessageTimestamp'] as Timestamp)
                  .toDate(),
              lastMessageStatus: data['lastMessageStatus'] ?? 'sent',
              lastSenderId: data['lastSenderId'] ?? '',
            );
          }

          // Refresh state from Hive
          state = _hiveService.getRecentChats();
        });
  }

  @override
  void dispose() {
    _firestoreSubscription?.cancel();
    super.dispose();
  }
}
