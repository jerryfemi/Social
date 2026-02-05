import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:social/models/message_search_result.dart';
import 'package:social/utils/date_utils.dart';

/// A tile that displays a message search result with highlighted query text
class SearchResultTile extends StatelessWidget {
  final MessageSearchResult result;
  final VoidCallback? onTap;

  const SearchResultTile({super.key, required this.result, this.onTap});

  @override
  Widget build(BuildContext context) {
    final dateUtil = DateUtil();
    final theme = Theme.of(context);

    // Determine what text to show (message or caption)
    final String displayText = result.message.message.isNotEmpty
        ? result.message.message
        : result.message.caption ?? '';

    // Get message type icon
    final typeIcon = _getTypeIcon(result.message.type);

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 3),
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile photo
            ClipOval(
              child:
                  result.chatPhotoUrl != null && result.chatPhotoUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: result.chatPhotoUrl!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => CircleAvatar(
                        backgroundColor: theme.colorScheme.secondary,
                        radius: 28,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (context, url, error) => CircleAvatar(
                        backgroundColor: theme.colorScheme.secondary,
                        radius: 28,
                        child: Icon(
                          result.isGroup ? Icons.group : Icons.person,
                          size: 26,
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                    )
                  : CircleAvatar(
                      backgroundColor: theme.colorScheme.secondary,
                      radius: 28,
                      child: Icon(
                        result.isGroup ? Icons.group : Icons.person,
                        size: 26,
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Chat name and time
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          result.chatName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Text(
                        dateUtil.formatMessageTime(result.message.timestamp),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),

                  // Sender name (for groups or if message is from other user)
                  Text(
                    result.message.senderName,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),

                  // Message with highlighted query
                  Row(
                    children: [
                      if (typeIcon != null) ...[
                        Icon(
                          typeIcon,
                          size: 16,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: _buildHighlightedText(
                          context,
                          displayText,
                          result.query,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns an icon based on message type
  IconData? _getTypeIcon(String type) {
    switch (type) {
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.videocam;
      case 'voice':
        return Icons.mic;
      case 'gif':
        return Icons.gif_box;
      case 'document':
        return Icons.insert_drive_file;
      default:
        return null;
    }
  }

  /// Builds rich text with the query highlighted
  Widget _buildHighlightedText(
    BuildContext context,
    String text,
    String query,
  ) {
    final theme = Theme.of(context);

    if (query.isEmpty) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    // Find all occurrences
    final List<TextSpan> spans = [];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        // Add remaining text
        if (start < text.length) {
          spans.add(
            TextSpan(
              text: text.substring(start),
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          );
        }
        break;
      }

      // Add text before match
      if (index > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, index),
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        );
      }

      // Add highlighted match (preserve original case)
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
          ),
        ),
      );

      start = index + query.length;
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }
}
