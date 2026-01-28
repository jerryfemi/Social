import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social/providers/chat_provider.dart';
import 'package:social/utils/date_utils.dart';

class ChatAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String receiverName;
  final String receiverId;
  final String? photoUrl;
  final Color? backgroundColor;
  final VoidCallback onProfileTap;
  final bool isSelectionMode;
  final int selectedCount;
  final List<Widget> actions;

  const ChatAppBar({
    super.key,
    required this.receiverName,
    required this.receiverId,
    required this.photoUrl,
    required this.backgroundColor,
    required this.onProfileTap,
    required this.isSelectionMode,
    required this.selectedCount,
    required this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateUtil = DateUtil();

    return AppBar(
      backgroundColor: backgroundColor,
      title: InkWell(
        onTap: onProfileTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: photoUrl != null && photoUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photoUrl!,
                      height: 44,
                      width: 44,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          const CircularProgressIndicator(),
                      errorWidget: (context, url, error) => Icon(
                        Icons.person,
                        size: 20,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    )
                  : CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      radius: 22,
                      child: Icon(
                        Icons.person,
                        size: 20,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            if (!isSelectionMode)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    receiverName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  // Typing indicator or Online status
                  Consumer(
                    builder: (context, ref, child) {
                      final typingAsync = ref.watch(
                        typingStatusProvider(receiverId),
                      );
                      final onlineAsync = ref.watch(
                        onlineStatusProvider(receiverId),
                      );
                      final isTyping = typingAsync.value ?? false;
                      final onlineData = onlineAsync.value;
                      final isOnline = onlineData?['isOnline'] ?? false;

                      // Priority: typing > online > last seen
                      if (isTyping) {
                        return Text(
                          'typing...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.primary,
                            fontStyle: FontStyle.italic,
                          ),
                        );
                      }

                      if (isOnline) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Active now',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        );
                      }

                      // Show last seen if not online
                      final lastSeen = onlineData?['lastSeen'];
                      if (lastSeen != null) {
                        return Text(
                          dateUtil.formatLastSeen(lastSeen),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        );
                      }

                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            if (isSelectionMode)
              Text(
                '$selectedCount',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
          ],
        ),
      ),
      actions: actions,
    );
  }
}
