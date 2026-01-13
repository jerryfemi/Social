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

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _searchQuery = '';
  final TextEditingController controller = TextEditingController();
  final chatservice = ChatService();
  final authService = AuthService();
  final _notificationService = NotificationService();
  StreamSubscription? _deliverySubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _deliverySubscription = chatservice.listenToIncomingMessages(
        authService.currentUser!.uid,
      );

      // INITIALIZE NOTIFICATIONS
      _notificationService.initNotifications();
    });
  }

  // dispose
  @override
  void dispose() {
    super.dispose();
    controller.dispose();
    _deliverySubscription?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Map<String, dynamic>>> homeStreamAsync =
        _searchQuery.isEmpty
        ? ref.watch(recentChatsProvider)
        : ref.watch(searchUsersProvider(_searchQuery));

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
              // Only show skeleton when loading AND no cached data exists
              if (homeStreamAsync.isLoading && !homeStreamAsync.hasValue) {
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

              // Get cached or fresh data
              final chats = homeStreamAsync.value ?? [];
              final error = homeStreamAsync.error;

              // Only show error if there's no cached data to display
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
