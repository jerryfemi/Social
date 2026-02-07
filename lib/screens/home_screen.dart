import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:social/models/message_search_result.dart';
import 'package:social/providers/recents_chats_provider.dart';
import 'package:social/services/auth_service.dart';
import 'package:social/services/chat_service.dart';
import 'package:social/services/hive_service.dart';
import 'package:social/services/notification_service.dart';
import 'package:social/services/sync_service.dart';
import 'package:social/utils/date_utils.dart';
import 'package:social/utils/new_chat_sheet.dart';
import 'package:social/widgets/chat_bubble.dart';
import 'package:social/widgets/my_sliver_app_bar.dart';
import 'package:social/widgets/search_bar.dart';
import 'package:social/widgets/search_result_tile.dart';
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
  final _hiveService = HiveService();
  bool isSelected = false;
  Set<String> selectedUserIds = {};
  List<Map<String, dynamic>> selectedUsersData = [];
  final _syncService = SyncService();
  StreamSubscription? _deliverySubscription;

  // Search state
  List<MessageSearchResult> _searchResults = [];
  bool _isSearching = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _deliverySubscription = chatservice.listenToIncomingMessages(
        authService.currentUser!.uid,
      );

      // Initialize SyncService for offline retry
      _syncService.init(authService.currentUser!.uid);

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
    _searchDebounce?.cancel();
    super.dispose();
  }

  // Perform message search with debouncing
  void _performSearch(String query) {
    _searchDebounce?.cancel();

    if (query.isEmpty) {
      setState(() {
        _searchQuery = '';
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _searchQuery = query;
      _isSearching = true;
    });

    // Debounce search by 300ms to avoid searching on every keystroke
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await _hiveService.searchAllMessages(
        query,
        authService.currentUser!.uid,
      );
      if (mounted && _searchQuery == query) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    });
  }

  void _toggleSelection(Map<String, dynamic> userData) {
    setState(() {
      final userId = userData['uid'];
      if (selectedUserIds.contains(userId)) {
        selectedUserIds.remove(userId);
        selectedUsersData.removeWhere((u) => u['uid'] == userId);

        if (selectedUserIds.isEmpty) {
          isSelected = false;
        }
      } else {
        selectedUserIds.add(userId);
        selectedUsersData.add(userData);
      }
    });
  }

  // ENTER SELECTION MODE(onLongPress userTile)
  void _enterSelectionMode(Map<String, dynamic> userData) {
    setState(() {
      isSelected = true;
      selectedUserIds.add(userData['uid']);
      selectedUsersData.add(userData);
    });
  }

  //EXIT SELECTION MODE
  void _exitSelectionMode() {
    setState(() {
      isSelected = false;
      selectedUserIds.clear();
      selectedUsersData.clear();
    });
  }

  Future<void> _showNewChatSheet() async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => NewChatSheet(
        selectedUserIds: selectedUserIds,
        preSelectedUsers: selectedUsersData,
      ),
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
    );

    // Clear selection after sheet closes
    _exitSelectionMode();
  }

  @override
  Widget build(BuildContext context) {
    final chatList = ref.watch(recentChatsProvider);
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          //  APP BAR
          MyAppBar(
            onPresed: _showNewChatSheet,
            text: selectedUserIds.length.toString(),
            isSelection: isSelected,
          ),

          // SEARCH BAR
          SliverPersistentHeader(
            pinned: false,
            delegate: SearchBarDelegate(
              controller: controller,
              onChanged: _performSearch,
            ),
          ),

          // CONTENT
          Builder(
            builder: (context) {
              // Show search results if searching
              if (_searchQuery.isNotEmpty) {
                if (_isSearching) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (_searchResults.isEmpty) {
                  return _buildEmptySearchState(context);
                }

                return _buildSearchResults(context);
              }

              // Normal chat list
              if (chatList.isEmpty) {
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

              final chats = chatList;

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
        final dateUtil = DateUtil();
        final bool isThisSelected = selectedUserIds.contains(userData['uid']);
        final bool isGroup = userData['isGroup'] == true;

        final chatRoomId = userData['chatRoomId'] ?? userData['uid'];

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Slidable(
            key: ValueKey(chatRoomId),
            closeOnScroll: true,
            endActionPane: ActionPane(
              motion: const ScrollMotion(),
              // Removed DismissiblePane to prevent "dismissed widget still in tree" error
              children: [
                SlidableAction(
                  onPressed: (context) =>
                      _confirmDelete(context, chatRoomId, isGroup),
                  autoClose: true,
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  icon: Icons.delete,
                  label: 'Delete',
                  borderRadius: BorderRadius.circular(12),
                ),
              ],
            ),
            child: UserTile(
              text: userData['username'],
              photourl: userData['profileImage'],
              isGroup: isGroup,
              onLongPress: isGroup ? null : () => _enterSelectionMode(userData),

              // Show checkmark if selected, otherwise show time
              trailing: isThisSelected
                  ? Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : (_searchQuery.isEmpty &&
                        userData['lastMessageTimestamp'] != null)
                  ? Text(
                      dateUtil.formatMessageTime(
                        userData['lastMessageTimestamp'],
                      ),
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
                              syncStatus: null,
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
              onTap: () {
                if (isSelected && !isGroup) {
                  _toggleSelection(userData);
                } else {
                  context.push(
                    '/chat/${userData['username']}/${userData['uid']}',
                    extra: {
                      'photoUrl': userData['profileImage'],
                      'isGroup': isGroup,
                    },
                  );
                }
              },
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

  // BUILD SEARCH RESULTS
  Widget _buildSearchResults(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          // Header showing result count
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '${_searchResults.length} message${_searchResults.length == 1 ? '' : 's'} found',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }

          final result = _searchResults[index - 1];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: SearchResultTile(
              result: result,
              onTap: () {
                // Navigate to chat and scroll to the specific message
                context.push(
                  '/chat/${result.chatName}/${result.navigateId}',
                  extra: {
                    'photoUrl': result.chatPhotoUrl,
                    'scrollToMessageId': result.message.localId,
                    'isGroup': result.isGroup,
                  },
                );
              },
            ),
          );
        },
        childCount: _searchResults.length + 1, // +1 for header
      ),
    );
  }

  // EMPTY SEARCH STATE
  Widget _buildEmptySearchState(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 60,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 20),
            Text(
              'No messages found for "$_searchQuery"',
              style: TextStyle(
                color: Theme.of(context).colorScheme.tertiary,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.tertiary.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, String chatId, bool isGroup) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isGroup ? 'Delete Group?' : 'Delete Chat?'),
        content: Text(
          isGroup
              ? 'You will leave this group and it will be removed from your list.'
              : 'This chat will be removed from your list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _handleDelete(chatId, isGroup);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _handleDelete(String chatId, bool isGroup) async {
    try {
      // Removing self from participants effectively "deletes" the chat from view
      // For groups, this is equivalent to leaving.
      await chatservice.deleteChat(chatId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting chat: $e')));
      }
    }
  }
}
