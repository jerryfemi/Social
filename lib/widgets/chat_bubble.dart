import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:social/widgets/link_preview_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:linkify/linkify.dart';
import 'package:social/utils/date_utils.dart';

import 'package:social/widgets/voice_message_bubble.dart';
import 'package:url_launcher/url_launcher.dart';

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
    this.onReplyTap,
    this.isHighlighted = false,
    this.isSelected = false,
    this.onTap,
    required this.onLongPress,
    this.isFirstInSequence = true,
    this.isLastInSequence = true,
    this.onRetry,
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
  final void Function(String replyToId)? onReplyTap;
  final bool isHighlighted;
  final bool isSelected;
  final VoidCallback? onTap; // For selection toggle
  final VoidCallback? onLongPress; // For entering selection mode
  final VoidCallback? onRetry; // For retrying failed messages

  // Grouping flags
  final bool isFirstInSequence;
  final bool isLastInSequence;

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

  @override
  Widget build(BuildContext context) {
    bool isImage = widget.data['type'] == 'image';
    bool isVideo = widget.data['type'] == 'video';
    bool isVoice = widget.data['type'] == 'voice';
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

    // Dynamic Border Radius for grouping effect
    final double largeRadius = 18.0;
    final double smallRadius = 4.0;

    BorderRadius bubbleRadius;
    if (widget.isSender) {
      bubbleRadius = BorderRadius.only(
        topLeft: Radius.circular(largeRadius),
        bottomLeft: Radius.circular(largeRadius),
        topRight: Radius.circular(
          widget.isFirstInSequence ? largeRadius : smallRadius,
        ),
        bottomRight: Radius.circular(
          widget.isLastInSequence ? largeRadius : smallRadius,
        ),
      );
    } else {
      bubbleRadius = BorderRadius.only(
        topRight: Radius.circular(largeRadius),
        bottomRight: Radius.circular(largeRadius),
        topLeft: Radius.circular(
          widget.isFirstInSequence ? largeRadius : smallRadius,
        ),
        bottomLeft: Radius.circular(
          widget.isLastInSequence ? largeRadius : smallRadius,
        ),
      );
    }

    // Dynamic vertical padding
    final double topPad = widget.isFirstInSequence ? 4.0 : 1.0;
    final double bottomPad = widget.isLastInSequence ? 4.0 : 1.0;

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
                  left: widget.isSender ? 10 : 0,
                  right: widget.isSender ? 0 : 10,
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
              onLongPress: widget.onLongPress,
              onTap: widget.onTap,
              child: Transform.translate(
                offset: Offset(offset, 0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  alignment: widget.alignment,
                  decoration: BoxDecoration(
                    color: (widget.isHighlighted || widget.isSelected)
                        ? Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: bubbleRadius,
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 8,
                      right: 8,
                      top: topPad,
                      bottom: bottomPad,
                    ),
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
                              borderRadius: bubbleRadius,
                            ),
                            child: IntrinsicWidth(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Reply quote if exists
                                  if (hasReply) _buildReplyQuote(context),

                                  isVoice
                                      ? VoiceMessageBubble(
                                          audioUrl: widget.data['message'],
                                          localFilePath:
                                              widget.data['localFilePath'],
                                          duration:
                                              widget.data['voiceDuration'] ?? 0,
                                          isSender: widget.isSender,
                                          bubbleColor: widget.bubbleColor,
                                          textTime: textTime,
                                          status:
                                              widget.data['status'] ?? 'read',
                                          syncStatus: widget.data['syncStatus'],
                                          onRetry: widget.onRetry,
                                        )
                                      : isMedia
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
    final replyToId = widget.data['replyToId'];
    final replyToSender = widget.data['replyToSender'] ?? '';
    final replyToMessage = widget.data['replyToMessage'] ?? '';
    final replyToType = widget.data['replyToType'] ?? 'text';
    final isMediaReply = replyToType == 'image' || replyToType == 'video';
    final isVoiceReply = replyToType == 'voice';

    String displayMessage;
    if (isVoiceReply) {
      displayMessage = '🎤 Voice message';
    } else if (isMediaReply) {
      displayMessage = '📷 Photo';
    } else {
      displayMessage = replyToMessage;
    }

    return GestureDetector(
      onTap: replyToId != null && widget.onReplyTap != null
          ? () => widget.onReplyTap!(replyToId)
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
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
              displayMessage,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: widget.isSender ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build placeholder for videos without thumbnail
  Widget _buildVideoPlaceholder() {
    return Container(
      height: 300,
      width: 250,
      color: Colors.grey[800],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam, color: Colors.white70, size: 50),
          const SizedBox(height: 8),
          Text("Video", style: TextStyle(color: Colors.white70, fontSize: 14)),
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
    final message = widget.data['message'] as String;
    final isGif = message.toLowerCase().contains('.gif');

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
                      extra: {'videoUrl': message, 'caption': caption},
                    )
                  : () => context.push(
                      '/viewImage',
                      extra: {
                        'photoUrl': message,
                        'caption': caption,
                        'senderName': widget.isSender
                            ? 'You'
                            : widget.senderName,
                        'timestamp': widget.data['timestamp'],
                      },
                    ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Hero(
                  tag: message,
                  child: isVideo && widget.data['thumbnailUrl'] != null
                      ? CachedNetworkImage(
                          imageUrl: widget.data['thumbnailUrl'],
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
                              child: Center(
                                child: const CircularProgressIndicator(),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) =>
                              _buildVideoPlaceholder(),
                        )
                      : isVideo
                      ? _buildVideoPlaceholder()
                      : (widget.data['localFilePath'] != null &&
                            widget.data['localFilePath'].isNotEmpty)
                      ? (kIsWeb
                            ? Image.network(
                                widget.data['localFilePath'],
                                height: 300,
                                width: 250,
                                fit: BoxFit.cover,
                              )
                            : Image.file(
                                File(widget.data['localFilePath']),
                                height: 300,
                                width: 250,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return CachedNetworkImage(
                                    imageUrl: message,
                                    height: 300,
                                    width: 250,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Skeleton.replace(
                                      height: 300,
                                      width: 250,
                                      child: Container(
                                        color: Colors.transparent.withValues(
                                          alpha: 0.4,
                                        ),
                                        height: 300,
                                        width: 250,
                                        child: Center(
                                          child:
                                              const CircularProgressIndicator(),
                                        ),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        Container(
                                          height: 300,
                                          width: 250,
                                          color: Colors.grey[300],
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.broken_image,
                                                color: Colors.red,
                                                size: 40,
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                "Failed to load",
                                                style: TextStyle(
                                                  color: Colors.red,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                  );
                                },
                              ))
                      : isGif
                      ? CachedNetworkImage(
                          imageUrl: message,
                          height: 200,
                          width: 220,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Skeleton.replace(
                            height: 200,
                            width: 220,
                            child: Container(
                              height: 200,
                              width: 220,
                              color: Colors.black12,
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[300],
                            height: 200,
                            width: 220,
                            child: const Icon(
                              Icons.broken_image,
                              color: Colors.red,
                            ),
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: message,
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
                              child: Center(
                                child: const CircularProgressIndicator(),
                              ),
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
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                  ),
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
                        StatusIcon(
                          status: widget.data['status'] ?? 'read',
                          syncStatus: widget.data['syncStatus'],
                          onRetry: widget.onRetry,
                        ),
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
                        StatusIcon(
                          status: widget.data['status'] ?? 'read',
                          syncStatus: widget.data['syncStatus'],
                          onRetry: widget.onRetry,
                        ),
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
    final bool isEdited = widget.data['isEdited'] == true;
    String message = widget.data['message'] ?? '';
    final hasLink = _containsLink(message);

    final List<LinkifyElement> elements = linkify(
      message,
      options: const LinkifyOptions(humanize: false),
      linkifiers: [const EmailLinkifier(), const UrlLinkifier()],
    );

    // 2. BUILD SPANS
    List<InlineSpan> textSpans = [];

    for (var element in elements) {
      if (element is LinkableElement) {
        // It's a link
        textSpans.add(
          TextSpan(
            text: element.text,
            style: TextStyle(
              color: Colors.white,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () async {
                final url = Uri.parse(element.url);
                if (!await launchUrl(
                  url,
                  mode: LaunchMode.externalApplication,
                )) {
                  // Handle error
                }
              },
          ),
        );
      } else {
        // It's normal text
        textSpans.add(
          TextSpan(
            text: element.text,
            style: TextStyle(
              fontSize: 14,
              color: widget.isSender ? Colors.white : Colors.black,
            ),
          ),
        );
      }
    }

    textSpans.add(const WidgetSpan(child: SizedBox(width: 70)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectionArea(
          child: Stack(
            children: [
              Text.rich(TextSpan(children: textSpans)),
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
                    if (isEdited)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Text(
                          'edited',
                          style: TextStyle(
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                            color: Colors.white60,
                          ),
                        ),
                      ),
                    Text(
                      textTime,
                      style: TextStyle(fontSize: 10, color: Colors.white60),
                    ),
                    if (widget.isSender) ...[
                      SizedBox(width: 3),
                      StatusIcon(
                        status: widget.data['status'] ?? 'read',
                        syncStatus: widget.data['syncStatus'],
                        onRetry: widget.onRetry,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (hasLink)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: LinkPreviewCard(
              url: _extractLink(message),
              isSender: widget.isSender,
            ),
          ),
      ],
    );
  }

  // helper to check if message contains link
  bool _containsLink(String text) {
    final urlRegExp = RegExp(
      r"((https?:www\.)|(https?:\/\/)|(www\.))[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9]{1,6}(\/[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)?",
      caseSensitive: false,
    );
    return urlRegExp.hasMatch(text);
  }

  String _extractLink(String text) {
    final urlRegExp = RegExp(
      r"((https?:www\.)|(https?:\/\/)|(www\.))[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9]{1,6}(\/[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)?",
      caseSensitive: false,
    );
    final match = urlRegExp.firstMatch(text)?.group(0);
    if (match != null && !match.startsWith('http')) {
      // AnyLinkPreview often needs http/https prefix
      return 'https://$match';
    }
    return match ?? '';
  }
}

class StatusIcon extends StatelessWidget {
  final String status;
  final String? syncStatus;
  final VoidCallback? onRetry;
  const StatusIcon({
    super.key,
    required this.status,
    required this.syncStatus,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    IconData? icon;
    Color? color;

    if (syncStatus != null) {
      if (syncStatus!.contains('failed')) {
        return GestureDetector(
          onTap: onRetry,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 14, color: Colors.red),
              if (onRetry != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.refresh, size: 14, color: Colors.red),
              ],
            ],
          ),
        );
      }
    }

    switch (status) {
      case 'pending':
        icon = Icons.access_time_rounded;
        color = Theme.of(context).colorScheme.inversePrimary;
        break;
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
        color = Colors.blue;
        break;
    }
    return Icon(icon, size: 13, color: color);
  }
}
