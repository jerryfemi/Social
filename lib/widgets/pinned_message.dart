import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social/providers/chat_provider.dart';

class PinnedMessageWidget extends ConsumerWidget {
  final Map<String, dynamic> pinnedData;
  final String receiverId;
  final Color color;
  final VoidCallback onTap;

  const PinnedMessageWidget({
    super.key,
    required this.pinnedData,
    required this.color,
    required this.receiverId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool canUnpin =
        true; // Anyone can unpin? Or only sender? Usually admins or both. Let's assume both.

    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.push_pin,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Pinned Message",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    pinnedData['message'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          if (canUnpin)
            GestureDetector(
              onTap: () {
                ref.read(chatServiceProvider).unpinMessage(receiverId);
              },
              child: Icon(Icons.close, size: 16, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}
