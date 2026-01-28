import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  final String? highlightedMessageId;

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
    this.highlightedMessageId,
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
        _scrollToMessage(widget.highlightedMessageId!);
      });
    }
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
    final name = isSender ? 'You' : widget.receiverName;

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
      onReply: () => widget.onReply(messageData, messageKey, name),
      onReplyTap: _scrollToMessage,
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
    );
  }

  void _scrollToMessage(String messageId) {
    // Logic to scroll to message (might need to coordinate with scroll controller or search logic)
    // For now, this internal logic mimics ChatScreen but we might need parent coordination
    // if the target message isn't rendered?
    // Actually, ListView.builder builds lazily. If message isn't built, GlobalKey context is null.
    // This simple logic only works if message is in view or built.
    // The previous implementation had the same limitation.

    // We need to find the index of the message?
    // For now, assume consistent behaviour.
    final key = _messageKeys[messageId];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.5,
      );
    }
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
}
