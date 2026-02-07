import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social/providers/chat_stats_provider.dart';

class ChatStatsLinear extends ConsumerWidget {
  final String chatRoomId;
  final String receiverName;

  const ChatStatsLinear({
    super.key,
    required this.chatRoomId,
    required this.receiverName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(chatStatsProvider(chatRoomId));
    final total = stats['total'] as int;
    final myPercent = stats['myPercent'] as double;

    // Guard against 0 messages
    if (total == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final myColor = theme.colorScheme.primary;
    final otherColor = theme.colorScheme.secondaryContainer;

    final myPercentString = (myPercent * 100).toStringAsFixed(0);
    final otherPercentString = ((1 - myPercent) * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Stats',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 12,
              child: LinearProgressIndicator(
                value: myPercent,
                backgroundColor: otherColor,
                color: myColor,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ME
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: myColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'You ($myPercentString%)',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              // THEM
              Row(
                children: [
                  Text(
                    '$receiverName ($otherPercentString%)',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: otherColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '$total Messages Total',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}
