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
  final bool isGroup;

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
    this.isGroup = false,
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
                        isGroup ? Icons.group : Icons.person,
                        size: 20,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    )
                  : CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      radius: 22,
                      child: Icon(
                        isGroup ? Icons.group : Icons.person,
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
                  // For groups, show member count or nothing
                  // For 1-on-1, show typing/online status
                  // Group Chat: Show typing/recording OR member list
                  if (isGroup)
                    Consumer(
                      builder: (context, ref, child) {
                        final gTypingAsync = ref.watch(
                          groupTypingStatusProvider(receiverId),
                        );
                        final gRecordingAsync = ref.watch(
                          groupRecordingStatusProvider(receiverId),
                        );
                        final groupInfoAsync = ref.watch(
                          groupInfoProvider(receiverId),
                        );

                        final typingMap = gTypingAsync.value ?? {};
                        final recordingMap = gRecordingAsync.value ?? {};

                        // 1. Recording (Priority)
                        if (recordingMap.isNotEmpty) {
                          return _buildGroupStatusText(
                            context,
                            ref,
                            recordingMap.keys.toList(),
                            'recording...',
                          );
                        }

                        // 2. Typing
                        if (typingMap.isNotEmpty) {
                          return _buildGroupStatusText(
                            context,
                            ref,
                            typingMap.keys.toList(),
                            'typing...',
                          );
                        }

                        // 3. Member List (Default)
                        // We need to fetch member names. This might be expensive to do here if not cached.
                        // Ideally, groupInfo contains participant IDs.
                        // We can show "X members" or fetch names if we have a provider for it.
                        // For now, let's show user counts or "Tap for info" which is standard if we don't have all user data loaded.
                        // OR we can try to show names if we have them in cache (UserProfileProvider).

                        return groupInfoAsync.when(
                          data: (doc) {
                            if (!doc.exists) return const SizedBox.shrink();
                            final data = doc.data() as Map<String, dynamic>;
                            final attendees = List<String>.from(
                              data['participants'] ?? [],
                            );

                            // If we want to show names, we'd need to resolve IDs to Names.
                            // That requires watching multiple user streams which is complex in a small widget.
                            // Simple fallback:
                            return Text(
                              '${attendees.length} members',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        );
                      },
                    )
                  else
                    // 1-on-1 Chat
                    Consumer(
                      builder: (context, ref, child) {
                        final typingAsync = ref.watch(
                          typingStatusProvider(receiverId),
                        );
                        final onlineAsync = ref.watch(
                          onlineStatusProvider(receiverId),
                        );
                        final recordingAsync = ref.watch(
                          recordingStatusProvider(receiverId),
                        );
                        final isRecording = recordingAsync.value ?? false;
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
                        if (isRecording) {
                          return Text(
                            'recording...',
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

  Widget _buildGroupStatusText(
    BuildContext context,
    WidgetRef ref,
    List<String> userIds,
    String action,
  ) {
    if (userIds.isEmpty) return const SizedBox.shrink();

    // We only resolve the first name for brevity: "John and 2 others are typing..."
    final firstUserId = userIds.first;
    final userAsync = ref.watch(userProfileProvider(firstUserId));

    return userAsync.when(
      data: (doc) {
        if (!doc.exists) return Text(action);
        final data = doc.data() as Map<String, dynamic>;
        final name = data['username'] ?? 'Member';

        String text;
        if (userIds.length == 1) {
          text = '$name is $action';
        } else if (userIds.length == 2) {
          text = '$name and 1 other are $action';
        } else {
          text = '$name and ${userIds.length - 1} others are $action';
        }

        return Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.primary,
            fontStyle: FontStyle.italic,
          ),
        );
      },
      loading: () => Text(
        'Members are $action',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.primary,
          fontStyle: FontStyle.italic,
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
