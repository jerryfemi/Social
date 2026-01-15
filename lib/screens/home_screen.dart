import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:skeletonizer/src/utils/bone_mock.dart';
import 'package:social/providers/chat_provider.dart';
import 'package:social/services/auth_service.dart';
import 'package:social/services/chat_service.dart';
import 'package:social/services/notification_service.dart';
import 'package:social/widgets/chat_bubble.dart';
import 'package:social/widgets/my_sliver_app_bar.dart';
import 'package:social/widgets/search_bar.dart';
import 'package:social/widgets/user_tile.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  String _searchQuery = '';
  final TextEditingController controller = TextEditingController();
  final chatservice = ChatService();
  final authService = AuthService();
  final _notificationService = NotificationService();
  StreamSubscription? _deliverySubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _deliverySubscription = chatservice.listenToIncomingMessages(
        authService.currentUser!.uid,
      );

      // Process any pending notification navigation (from terminated state)
      _notificationService.processPendingNotification();

      // Clear notifications when home screen opens
      _notificationService.clearAllNotifications();

      // Set user as online
      chatservice.setOnlineStatus(true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Clear all notifications when app comes to foreground
      _notificationService.clearAllNotifications();
      // Set user as online
      chatservice.setOnlineStatus(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Set user as offline when app goes to background
      chatservice.setOnlineStatus(false);
    }
  }

  // dispose
  @override
  void dispose() {
    // Set user as offline when leaving
    chatservice.setOnlineStatus(false);
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    _deliverySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Map<String, dynamic>>> homeStreamAsync =
        _searchQuery.isEmpty
        ? ref.watch(recentChatsProvider)
        : ref.watch(searchUsersProvider(_searchQuery));

    // Get cached data for initial display
    final cachedChats = _searchQuery.isEmpty
        ? ref.watch(cachedRecentChatsProvider)
        : const AsyncValue<List<Map<String, dynamic>>?>.data(null);

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          //  APP BAR
          MyAppBar(),

          // SEARCH BAR
          SliverPersistentHeader(
            pinned: false,
            delegate: SearchBarDelegate(
              controller: controller,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),

          // CONTENT
          // Show cached data immediately, only show skeleton when truly no data
          Builder(
            builder: (context) {
              // Get cached data if available
              final cached = cachedChats.value;

              // Only show skeleton when loading AND no cached data AND no stream data
              if (homeStreamAsync.isLoading &&
                  !homeStreamAsync.hasValue &&
                  (cached == null || cached.isEmpty)) {
                return Skeletonizer.sliver(
                  enabled: true,
                  child: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: UserTile(
                          text: BoneMock.name,
                          photourl: null,
                          subtitle: Text(BoneMock.words(4)),
                          onTap: null,
                        ),
                      );
                    }, childCount: 8),
                  ),
                );
              }

              // Use fresh data if available, otherwise fall back to cached data
              final chats = homeStreamAsync.value ?? cached ?? [];
              final error = homeStreamAsync.error;

              // Only show error if there's no data to display at all
              if (error != null && chats.isEmpty) {
                return SliverFillRemaining(
                  child: const Center(child: Text('Error')),
                );
              }

              if (chats.isEmpty) {
                return _buildEmptyState(context);
              }

              return _buildContent(context, chats);
            },
          ),
        ],
      ),
    );
  }

  // -------------------------------------------EXTRACTED--------------------------------------------

  // Format message time for display
  String _formatMessageTime(dynamic timestamp) {
    DateTime messageTime;

    if (timestamp is int) {
      messageTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else if (timestamp != null &&
        timestamp.runtimeType.toString().contains('Timestamp')) {
      messageTime = (timestamp as dynamic).toDate();
    } else {
      return '';
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(
      messageTime.year,
      messageTime.month,
      messageTime.day,
    );

    if (messageDate == today) {
      // Today - show time only
      final hour = messageTime.hour;
      final minute = messageTime.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$hour12:$minute $period';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      // Yesterday
      return 'Yesterday';
    } else if (now.difference(messageTime).inDays < 7) {
      // Within last week - show day name
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[messageTime.weekday - 1];
    } else {
      // Older - show date
      return '${messageTime.day}/${messageTime.month}/${messageTime.year}';
    }
  }

  // BUILD CONTENT6
  Widget _buildContent(
    BuildContext context,
    List<Map<String, dynamic>> dataList,
  ) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final userData = dataList[index];
        bool isMe = userData['lastSenderId'] == authService.currentUser!.uid;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: UserTile(
            text: userData['username'],
            photourl: userData['profileImage'],

            // Show last message time
            trailing:
                (_searchQuery.isEmpty &&
                    userData['lastMessageTimestamp'] != null)
                ? Text(
                    _formatMessageTime(userData['lastMessageTimestamp']),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  )
                : null,

            // Show last message if in Recent chats
            subtitle:
                (_searchQuery.isEmpty &&
                    userData['lastMessage'] != null &&
                    userData['lastMessage'].isNotEmpty)
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isMe && userData['lastMessageStatus'] != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: StatusIcon(
                            status: userData['lastMessageStatus'],
                          ),
                        ),

                      Flexible(
                        child: Text(
                          userData['lastMessage'].toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : null,
            onTap: () => context.push(
              '/chat/${userData['username']}/${userData['uid']}',
              extra: userData['profileImage'],
            ),
          ),
        );
      }, childCount: dataList.length),
    );
  }

  //  EMPTY STATES
  Widget _buildEmptyState(BuildContext context) {
    bool isSearching = _searchQuery.isNotEmpty;

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearching ? Icons.search_off : Icons.chat_bubble_outline,
              size: 60,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 20),
            Text(
              isSearching
                  ? 'No users found named "$_searchQuery"'
                  : 'No chats yet.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.tertiary,
                fontSize: 16,
              ),
            ),
            if (!isSearching)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Search above to start chatting!',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.tertiary,
                    fontSize: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
