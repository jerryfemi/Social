import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:social/providers/chat_provider.dart';
import 'package:social/utils/date_utils.dart';
import 'package:social/widgets/my_alert_dialog.dart';

class ChatBubble extends ConsumerWidget {
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
                isStarred ? Icons.star : Icons.star_border,
                color: isStarred ? Colors.orange : null,
              ),
              title: Text(isStarred ? 'Unstar' : 'Star'),
              onTap: () {
                context.pop();
                ref
                    .read(chatServiceProvider)
                    .toggleStarMessage(data, messageId, receiverId);
              },
            ),
            // report message
            if (!isSender)
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
  Widget build(BuildContext context, WidgetRef ref) {
    bool isImage = data['type'] == 'image';
    bool isVideo = data['type'] == 'video';
    bool isMedia = isImage || isVideo;
    final String? caption = data['caption'];
    final textTime = DateUtil.getFormattedTime(data['timestamp']);

    return GestureDetector(
      onLongPress: () {
        showOptions(context, ref, messageId, userId, receiverId);
      },
      child: Container(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: isSender
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              // Bubble
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 250),
                child: Container(
                  padding: isMedia
                      ? const EdgeInsets.all(4)
                      : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        bubbleColor.withValues(alpha: 0.9),
                        Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.8),
                      ],
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                    ),
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
            ],
          ),
        ),
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
                      extra: {'videoUrl': data['message'], 'caption': caption},
                    )
                  : () => context.push(
                      '/viewImage',
                      extra: {'photoUrl': data['message'], 'caption': caption},
                    ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Hero(tag:  data['message'],
                  child: CachedNetworkImage(
                    imageUrl: data['message'],
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
                    extra: {'videoUrl': data['message'], 'caption': caption},
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
                      if (isStarred)
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
                      if (isSender) ...[
                        const SizedBox(width: 3),
                        StatusIcon(status: data['status'] ?? 'read'),
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
                      color: isSender ? Colors.white : Colors.black,
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
                      if (isStarred)
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
                      if (isSender) ...[
                        SizedBox(width: 4),
                        StatusIcon(status: data['status'] ?? 'read'),
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
            text: data['message'],
            style: TextStyle(
              fontSize: 14,
              color: isSender ? Colors.white : Colors.black,
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
              if (isStarred)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Icon(Icons.star, size: 12, color: Colors.orange),
                ),
              Text(
                textTime,
                style: TextStyle(fontSize: 10, color: Colors.white60),
              ),
              if (isSender) ...[
                SizedBox(width: 3),
                StatusIcon(status: data['status'] ?? 'read'),
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
