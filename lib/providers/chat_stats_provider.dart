import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social/providers/chat_message_provider.dart';
import 'package:social/services/auth_service.dart';

// Returns a Map with:
// 'total': int
// 'myCount': int
// 'othersCount': int (for 1-on-1)
// 'counts': Map<String, int> (senderId -> count)
// 'myPercent': double
final chatStatsProvider = Provider.family<Map<String, dynamic>, String>((
  ref,
  chatRoomId,
) {
  final messagesAsync = ref.watch(chatMessagesProvider(chatRoomId));

  return messagesAsync.when(
    data: (messages) {
      if (messages.isEmpty) {
        return {
          'total': 0,
          'myCount': 0,
          'othersCount': 0,
          'counts': <String, int>{},
          'myPercent': 0.0,
        };
      }

      final currentUserId = AuthService().currentUser!.uid;
      final total = messages.length;
      int myCount = 0;
      final Map<String, int> counts = {};

      for (var msg in messages) {
        final senderId = msg.senderID;
        counts[senderId] = (counts[senderId] ?? 0) + 1;
        if (senderId == currentUserId) {
          myCount++;
        }
      }

      final othersCount = total - myCount;
      final myPercent = (myCount / total);

      return {
        'total': total,
        'myCount': myCount,
        'othersCount': othersCount,
        'counts': counts,
        'myPercent': myPercent,
      };
    },
    error: (_, __) => {
      'total': 0,
      'myCount': 0,
      'othersCount': 0,
      'counts': <String, int>{},
      'myPercent': 0.0,
    },
    loading: () => {
      'total': 0,
      'myCount': 0,
      'othersCount': 0,
      'counts': <String, int>{},
      'myPercent': 0.0,
    },
  );
});
