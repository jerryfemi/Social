import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:social/models/message_hive.dart' as hive_model;
import 'package:social/providers/chat_message_provider.dart';
import 'package:social/providers/chat_provider.dart';
import 'package:social/services/auth_service.dart';
import 'package:social/utils/date_utils.dart';
import 'package:social/widgets/chat_bubble.dart';

class MessageListView extends ConsumerStatefulWidget {
  final String chatRoomId;
  final String receiverId;
  final String receiverName;
  final ScrollController scrollController;
  final bool isSelectionMode;
  final Set<String> selectedMessageIds;
  final Function(String) onEnterSelectionMode;
  final Function(String) onToggleSelection;
  final Function(Map<String, dynamic>, String, String) onReply;
  final Function(String) onScrollToMessage;
  final String? highlightedMessageId;
  final bool isGroup;
  final Function(String)? onMediaTap;

  const MessageListView({
    super.key,
    required this.chatRoomId,
    required this.receiverId,
    required this.receiverName,
    required this.scrollController,
    required this.isSelectionMode,
    required this.selectedMessageIds,
    required this.onEnterSelectionMode,
    required this.onToggleSelection,
    required this.onReply,
    required this.onScrollToMessage,
    this.highlightedMessageId,
    this.isGroup = false,
    this.onMediaTap,
  });

  @override
  ConsumerState<MessageListView> createState() => _MessageListViewState();
}

class _MessageListViewState extends ConsumerState<MessageListView> {
  final AuthService authService = AuthService();
  final Map<String, GlobalKey> _messageKeys = {};

  @override
  void didUpdateWidget(MessageListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightedMessageId != null &&
        widget.highlightedMessageId != oldWidget.highlightedMessageId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToHighlightedMessage();
      });
    }
  }

  bool _isScrollingToMessage = false;

  Future<void> _scrollToHighlightedMessage() async {
    final messageId = widget.highlightedMessageId;
    if (messageId == null || _isScrollingToMessage) return;

    _isScrollingToMessage = true;

    try {
      // Step 1: Check if already rendered (Fastest)
      final key = _messageKeys[messageId];
      if (key?.currentContext != null) {
        await _scrollToExistingKey(key!);
        return;
      }

      // Step 2: Find message index for off-screen jump
      final messagesAsync = ref.read(chatMessagesProvider(widget.chatRoomId));
      final messages = messagesAsync.asData?.value;
      if (messages == null || messages.isEmpty) return;

      final reversedMessages = messages.reversed.toList();
      final targetIndex = reversedMessages.indexWhere(
        (m) => m.localId == messageId,
      );

      if (targetIndex == -1) return;

      // Step 3: Jump near the target using Ratio
      // (Target / Total) * MaxScroll gives a decent approximation
      await _jumpToApproximatePosition(targetIndex, reversedMessages.length);
      if (!mounted) return;
      // Step 4: Wait for render, then fine-tune
      // Give the list a moment to build the items at the new offset
      await Future(() {
        if (mounted) return WidgetsBinding.instance.endOfFrame;
      });
      // Try finding the key again
      // We might need to schedule a post-frame callback if it's still building
      if (mounted) {
        final keyAfterJump = _messageKeys[messageId];
        if (keyAfterJump?.currentContext != null) {
          await _scrollToExistingKey(keyAfterJump!);
        }
      }
    } catch (e) {
      debugPrint('Scroll error: $e');
    } finally {
      if (mounted) {
        _isScrollingToMessage = false;
      }
    }
  }

  Future<void> _scrollToExistingKey(GlobalKey key) async {
    final context = key.currentContext;
    if (context != null && context.mounted) {
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.5,
      );
    }
  }

  Future<void> _jumpToApproximatePosition(
    int targetIndex,
    int totalCount,
  ) async {
    if (!widget.scrollController.hasClients) return;

    final scrollController = widget.scrollController;
    final maxScroll = scrollController.position.maxScrollExtent;

    if (maxScroll <= 0) return;

    // Calculate position
    // Since reverse: true, index 0 is at bottom (position 0)
    // and last index is at top (maxScrollExtent)
    final ratio = targetIndex / totalCount;
    final targetPosition = maxScroll * ratio;

    // Use jumpTo for instant movement (prevents "scrolling past" huge lists)
    // or animateTo for smoothness. Jump is safer for massive distances.
    scrollController.jumpTo(targetPosition.clamp(0.0, maxScroll));
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatMessagesProvider(widget.chatRoomId));

    return Padding(
      padding: const EdgeInsets.only(left: 15, right: 15, top: 5),
      child: messagesAsync.when(
        loading: () => _buildSkeletonMessages(),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text('Error loading messages'),
              const SizedBox(height: 8),
              Text(error.toString(), style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        data: (messages) {
          if (messages.isEmpty) {
            return const Center(child: Text('No Messages yet'));
          }

          final reversedMessages = messages.reversed.toList();

          return ListView.builder(
            reverse: true,
            controller: widget.scrollController,
            padding: const EdgeInsets.only(top: 10, bottom: 90),
            itemCount: reversedMessages.length,
            itemBuilder: (context, index) {
              return _buildMessageItemWithDate(
                reversedMessages,
                index,
                context,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMessageItemWithDate(
    List<hive_model.Message> messages,
    int index,
    BuildContext context,
  ) {
    final message = messages[index];
    final messageDate = message.timestamp;
    bool showHeader = false;

    if (index == messages.length - 1) {
      showHeader = true;
    } else {
      final nextMessage = messages[index + 1];
      final nextDate = nextMessage.timestamp;
      if (!DateUtil.isSameDay(messageDate, nextDate)) {
        showHeader = true;
      }
    }

    bool isLast = false;
    if (index == 0) {
      isLast = true;
    } else {
      final newerMsg = messages[index - 1];
      if (newerMsg.senderID != message.senderID) {
        isLast = true;
      } else if (!DateUtil.isSameDay(message.timestamp, newerMsg.timestamp)) {
        isLast = true;
      }
    }

    bool isFirst = false;
    if (index == messages.length - 1) {
      isFirst = true;
    } else {
      final olderMsg = messages[index + 1];
      if (olderMsg.senderID != message.senderID) {
        isFirst = true;
      } else if (!DateUtil.isSameDay(message.timestamp, olderMsg.timestamp)) {
        isFirst = true;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) _buildDateHeader(messageDate),
        _buildHiveMessageItem(
          message,
          context,
          isFirstInSequence: isFirst,
          isLastInSequence: isLast,
        ),
      ],
    );
  }

  Widget _buildHiveMessageItem(
    hive_model.Message message,
    BuildContext context, {
    required bool isFirstInSequence,
    required bool isLastInSequence,
  }) {
    final currentUserId = authService.currentUser!.uid;
    final isSender = message.senderID == currentUserId;
    final alignment = isSender ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor = isSender ? Colors.purpleAccent : Colors.grey;

    // For group chats, use the actual sender name from the message
    // For 1-on-1 chats, use 'You' or receiverName
    final name = isSender
        ? 'You'
        : (widget.isGroup ? message.senderName : widget.receiverName);

    final starredAsync = ref.watch(starredMessagesProvider);
    final starredIds = starredAsync.value?.docs.map((e) => e.id).toSet() ?? {};
    final isStarred =
        message.fireStoreId != null && starredIds.contains(message.fireStoreId);

    final messageKey = message.localId;
    _messageKeys.putIfAbsent(messageKey, () => GlobalKey());

    final messageData = _convertHiveMessageToMap(message);
    final isSelected = widget.selectedMessageIds.contains(message.localId);

    return ChatBubble(
      key: _messageKeys[messageKey],
      senderName: name,
      messageId: message.localId,
      userId: message.senderID,
      alignment: alignment,
      isSender: isSender,
      data: messageData,
      bubbleColor: bubbleColor,
      receiverId: widget.receiverId,
      isStarred: isStarred,
      isHighlighted: widget.highlightedMessageId == messageKey,
      isSelected: isSelected,
      isFirstInSequence: isFirstInSequence,
      isLastInSequence: isLastInSequence,
      showSenderName: widget.isGroup, // Show sender name in group chats
      onReply: () => widget.onReply(messageData, messageKey, name),
      onReplyTap: (id) => widget.onScrollToMessage(id),
      onLongPress: () {
        if (widget.isSelectionMode) {
          widget.onToggleSelection(message.localId);
        } else {
          widget.onEnterSelectionMode(message.localId);
        }
      },
      onTap: () {
        if (widget.isSelectionMode) {
          widget.onToggleSelection(message.localId);
        }
      },
      onRetry: () {
        ref
            .read(chatMessagesProvider(widget.chatRoomId).notifier)
            .retryMessage(message.localId);
      },
      onMediaTap: () => _openMediaGallery(message.localId),
    );
  }

  Widget _buildSkeletonMessages() {
    return Skeletonizer(
      enabled: true,
      child: ListView.builder(
        itemCount: 10,
        itemBuilder: (context, index) {
          final isSender = index % 2 == 0;
          return ChatBubble(
            alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
            isSender: isSender,
            data: {
              'message': BoneMock.paragraph,
              'timestamp': Timestamp.now(),
              'type': 'text',
              'status': 'read',
            },
            bubbleColor: isSender ? Colors.purpleAccent : Colors.grey,
            messageId: '',
            userId: '',
            senderName: '',
            receiverId: '',
            onLongPress: null,
          );
        },
      ),
    );
  }

  Widget _buildDateHeader(DateTime date) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        margin: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(DateUtil.getDateLabel(date)),
      ),
    );
  }

  // TODO: Move this to a central model extension or util
  Map<String, dynamic> _convertHiveMessageToMap(hive_model.Message msg) {
    return {
      'senderID': msg.senderID,
      'senderEmail': msg.senderEmail,
      'senderName': msg.senderName,
      'receiverId': msg.receiverID,
      'message': msg.message,
      'timestamp': Timestamp.fromDate(msg.timestamp),
      'type': msg.type,
      'caption': msg.caption,
      'status': msg.status,
      'replyToId': msg.replyToId,
      'replyToMessage': msg.replyToMessage,
      'replyToSender': msg.replyToSender,
      'replyToType': msg.replyToType,
      'voiceDuration': msg.voiceDuration,
      'thumbnailUrl': msg.thumbnailUrl,
      'isEdited': msg.isEdited,
      'editedAt': msg.editedAt != null
          ? Timestamp.fromDate(msg.editedAt!)
          : null,
      'deletedFor': msg.deletedFor,
      'localFilePath': msg.localFilePath,
      'syncStatus': msg.syncStatus.toString(),
    };
  }

  void _openMediaGallery(String startMessageId) {
    if (widget.onMediaTap != null) {
      widget.onMediaTap!(startMessageId);
      return;
    }

    // Default implementation: Gather media messages and navigate
    final messages = ref.read(chatMessagesProvider(widget.chatRoomId)).value;
    if (messages == null) return;

    final mediaMessages = messages
        .where((m) => m.type == 'image' || m.type == 'video')
        .map((m) => _convertHiveMessageToMap(m))
        .toList();

    // Sort by timestamp (though usually already sorted? Hive messages likely come sorted or we reversed them)
    // The list is "reversedMessages" in build, but here we access the provider's list which is raw.
    // Let's ensure chronological order for the gallery usually.
    // Provider list is usually sorted by timestamp desc or asc depending on query.
    // Let's assume ascending for gallery (oldest to newest) or descending?
    // Usually gallery shows chronologically.
    // If the provider returns DESC (newest first), we might want to reverse it.
    mediaMessages.sort((a, b) {
      final t1 = a['timestamp'] as Timestamp;
      final t2 = b['timestamp'] as Timestamp;
      return t1.compareTo(t2);
    });

    // We can use the startMessageId to scroll to the initial index if we were navigating to gallery from here
    // but typically we push to gallery from the Media Tile or similar.
    // If we want to open gallery from a specific message in the list, we'd need this logic.
    // For now, it's unused.
    // I should check _convertHiveMessageToMap again.
    // Yes, 'localFilePath' is there but 'id' (localId) is not there explicitly unless I add it.
    // Let's assume startMessageId matches 'message' (url) or 'localFilePath' for now, or better:
    // I will add localId to the map in _convertHiveMessageToMap!

    // But for now, let's find index by... well, I can't easily without ID.
    // Let's update _convertHiveMessageToMap to include 'id'.

    // Fallback: use loop with Hive objects to find index first?
    int index = 0;
    // Better: Filter hive messages first, find index, then convert.
    final sortedMedia = messages
        .where((m) => m.type == 'image' || m.type == 'video')
        .toList();
    sortedMedia.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    index = sortedMedia.indexWhere((m) => m.localId == startMessageId);
    if (index == -1) index = 0;

    final mediaMaps = sortedMedia
        .map((m) => _convertHiveMessageToMap(m))
        .toList();

    context.push(
      '/media_gallery',
      extra: {'mediaMessages': mediaMaps, 'initialIndex': index},
    );
  }
}
