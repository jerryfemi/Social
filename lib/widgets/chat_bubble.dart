import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:social/providers/chat_provider.dart';
import 'package:social/utils/date_utils.dart';
import 'package:social/widgets/my_alert_dialog.dart';

class ChatBubble extends ConsumerStatefulWidget {
  const ChatBubble({
    super.key,
    required this.alignment,
    required this.isSender,
    required this.data,
    required this.bubbleColor,
    required this.messageId,
    required this.userId,
    required this.senderName,
    required this.receiverId,
    this.isStarred = false,
    this.onReply,
  });

  final Alignment alignment;
  final bool isSender;
  final Map<String, dynamic> data;
  final ColorSwatch<int> bubbleColor;
  final String messageId;
  final String userId;
  final String senderName;
  final String receiverId;
  final bool isStarred;
  final void Function()? onReply;

  @override
  ConsumerState<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends ConsumerState<ChatBubble>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  late AnimationController _animationController;
  late Animation<double> _animation;

  // Swipe threshold to trigger reply
  static const double _swipeThreshold = 35;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      // For sender (right side): swipe left (negative)
      // For receiver (left side): swipe right (positive)
      if (widget.isSender) {
        _dragOffset += details.delta.dx;
        _dragOffset = _dragOffset.clamp(-60.0, 0.0);
      } else {
        _dragOffset += details.delta.dx;
        _dragOffset = _dragOffset.clamp(0.0, 60.0);
      }
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final shouldTriggerReply = widget.isSender
        ? _dragOffset < -_swipeThreshold
        : _dragOffset > _swipeThreshold;

    if (shouldTriggerReply) {
      widget.onReply?.call();
    }

    // Animate back to original position
    _animation = Tween<double>(begin: _dragOffset, end: 0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward(from: 0).then((_) {
      setState(() => _dragOffset = 0);
    });
  }

  // show options
  void showOptions(
    BuildContext context,
    WidgetRef ref,
    String messageId,
    String userId,
    String otherUserId,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            // star message
            ListTile(
              leading: Icon(
                widget.isStarred ? Icons.star : Icons.star_border,
                color: widget.isStarred ? Colors.orange : null,
              ),
              title: Text(widget.isStarred ? 'Unstar' : 'Star'),
              onTap: () {
                context.pop();
                ref
                    .read(chatServiceProvider)
                    .toggleStarMessage(
                      widget.data,
                      messageId,
                      widget.receiverId,
                    );
              },
            ),
            // report message
            if (!widget.isSender)
              ListTile(
                leading: Icon(Icons.flag),
                title: Text('report'),
                onTap: () {
                  context.pop();
                  report(context, ref, messageId, userId);
                },
              ),
            // delete message
            ListTile(
              leading: Icon(Icons.delete_rounded),
              title: Text('delete'),
              onTap: () {
                context.pop();
                deleteMessage(context, ref, messageId, otherUserId);
              },
            ),
          ],
        ),
      ),
    );
  }

  // report user
  void report(
    BuildContext context,
    WidgetRef ref,
    String messageId,
    String userId,
  ) {
    showDialog(
      context: context,
      builder: (context) => MyAlertDialog(
        content: 'Are you sure you want to report this message?',
        title: 'Report',
        text: 'report',
        onpressed: () {
          ref.read(chatServiceProvider).reportUser(messageId, userId);

          context.pop();
          context.pop();

          // show snackbar
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Report sent'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }

  // delete message
  void deleteMessage(
    BuildContext context,
    WidgetRef ref,
    String messageId,
    String otherUserId,
  ) {
    showDialog(
      context: context,
      builder: (context) => MyAlertDialog(
        content: 'Are you sure you want to delete this message?',
        title: 'Delete Message',
        text: 'delete',
        onpressed: () {
          ref.read(chatServiceProvider).deleteMessage(otherUserId, messageId);

          context.pop();

          // show snackbar
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Message deleted'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isImage = widget.data['type'] == 'image';
    bool isVideo = widget.data['type'] == 'video';
    bool isMedia = isImage || isVideo;
    final String? caption = widget.data['caption'];
    final textTime = DateUtil.getFormattedTime(widget.data['timestamp']);

    // Check if there's a reply
    final hasReply = widget.data['replyToMessage'] != null;

    // Calculate reply icon opacity based on drag distance
    final replyIconOpacity =
        (widget.isSender
                ? (-_dragOffset / _swipeThreshold)
                : (_dragOffset / _swipeThreshold))
            .clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final offset = _animationController.isAnimating
            ? _animation.value
            : _dragOffset;

        return Stack(
          alignment: widget.isSender
              ? Alignment.centerLeft
              : Alignment.centerRight,
          children: [
            // Reply icon (appears behind the bubble)
            Opacity(
              opacity: replyIconOpacity,
              child: Padding(
                padding: EdgeInsets.only(
                  left: widget.isSender ? 20 : 0,
                  right: widget.isSender ? 0 : 20,
                ),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.reply,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
              ),
            ),

            // Chat Bubble
            GestureDetector(
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              onLongPress: () {
                showOptions(
                  context,
                  ref,
                  widget.messageId,
                  widget.userId,
                  widget.receiverId,
                );
              },
              child: Transform.translate(
                offset: Offset(offset, 0),
                child: Container(
                  alignment: widget.alignment,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: widget.isSender
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        // Bubble
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 250),
                          child: Container(
                            padding: isMedia
                                ? const EdgeInsets.all(4)
                                : const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  widget.bubbleColor.withValues(alpha: 0.9),
                                  Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.8),
                                ],
                                begin: Alignment.bottomLeft,
                                end: Alignment.topRight,
                              ),
                              color: widget.bubbleColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IntrinsicWidth(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Reply quote if exists
                                  if (hasReply) _buildReplyQuote(context),

                                  isMedia
                                      ? _buildMediaContent(
                                          context,
                                          isVideo: isVideo,
                                          caption: caption,
                                          textTime: textTime,
                                        )
                                      : _buildTextContent(context, textTime),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // BUILD REPLY QUOTE (shown inside bubble)
  Widget _buildReplyQuote(BuildContext context) {
    final replyToSender = widget.data['replyToSender'] ?? '';
    final replyToMessage = widget.data['replyToMessage'] ?? '';
    final replyToType = widget.data['replyToType'] ?? 'text';
    final isMediaReply = replyToType == 'image' || replyToType == 'video';

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: widget.isSender
                ? Colors.white70
                : Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            replyToSender,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: widget.isSender
                  ? Colors.white
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isMediaReply ? '📷 Photo' : replyToMessage,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: widget.isSender ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  // BUILD MEDIA CONTENT (Image or Video)
  Widget _buildMediaContent(
    BuildContext context, {
    required bool isVideo,
    required String? caption,
    required String textTime,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Media (Image or Video thumbnail)
        Stack(
          children: [
            // Tappable media
            GestureDetector(
              onTap: isVideo
                  ? () => context.push(
                      '/videoPlayer',
                      extra: {
                        'videoUrl': widget.data['message'],
                        'caption': caption,
                      },
                    )
                  : () => context.push(
                      '/viewImage',
                      extra: {
                        'photoUrl': widget.data['message'],
                        'caption': caption,
                      },
                    ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Hero(
                  tag: widget.data['message'],
                  child: CachedNetworkImage(
                    imageUrl: widget.data['message'],
                    height: 300,
                    width: 250,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Skeleton.replace(
                      height: 300,
                      width: 250,
                      child: Container(
                        color: Colors.transparent.withValues(alpha: 0.4),
                        height: 300,
                        width: 250,
                        child: Center(child: const CircularProgressIndicator()),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 300,
                      width: 250,
                      color: Colors.grey[300],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.broken_image,
                            color: Colors.red,
                            size: 40,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            "Failed to load",
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Play button overlay for videos
            if (isVideo)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => context.push(
                    '/videoPlayer',
                    extra: {
                      'videoUrl': widget.data['message'],
                      'caption': caption,
                    },
                  ),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),

            // Time/status overlay (only if no caption)
            if (caption == null || caption.isEmpty)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isStarred)
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: Icon(
                            Icons.star,
                            size: 12,
                            color: Colors.orange,
                          ),
                        ),
                      Text(
                        textTime,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                        ),
                      ),
                      if (widget.isSender) ...[
                        const SizedBox(width: 3),
                        StatusIcon(status: widget.data['status'] ?? 'read'),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),

        // Caption (if exists)
        if (caption != null && caption.isNotEmpty)
          Padding(
            padding: EdgeInsetsGeometry.symmetric(horizontal: 4, vertical: 3),
            child: Stack(
              children: [
                Text.rich(
                  TextSpan(
                    text: caption,
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.isSender ? Colors.white : Colors.black,
                    ),
                    children: [const WidgetSpan(child: SizedBox(width: 75))],
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isStarred)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.star,
                            size: 12,
                            color: Colors.orange,
                          ),
                        ),
                      Text(
                        textTime,
                        style: TextStyle(fontSize: 10, color: Colors.white60),
                      ),
                      if (widget.isSender) ...[
                        SizedBox(width: 4),
                        StatusIcon(status: widget.data['status'] ?? 'read'),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // BUILD TEXT CONTENT
  Widget _buildTextContent(BuildContext context, String textTime) {
    return Stack(
      children: [
        Text.rich(
          TextSpan(
            text: widget.data['message'],
            style: TextStyle(
              fontSize: 14,
              color: widget.isSender ? Colors.white : Colors.black,
            ),
            children: [const WidgetSpan(child: SizedBox(width: 75))],
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isStarred)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Icon(Icons.star, size: 12, color: Colors.orange),
                ),
              Text(
                textTime,
                style: TextStyle(fontSize: 10, color: Colors.white60),
              ),
              if (widget.isSender) ...[
                SizedBox(width: 3),
                StatusIcon(status: widget.data['status'] ?? 'read'),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class StatusIcon extends StatelessWidget {
  final String status;
  const StatusIcon({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    IconData? icon;
    Color? color;

    switch (status) {
      case 'sent':
        icon = Icons.check_rounded;
        color = Theme.of(context).colorScheme.inversePrimary;
        break;

      case 'delivered':
        icon = Icons.done_all_rounded;
        color = Theme.of(context).colorScheme.inversePrimary;
        break;

      case 'read':
        icon = Icons.done_all_rounded;
        color = Colors.greenAccent;
        break;
    }
    return Icon(icon, size: 13, color: color);
  }
}
