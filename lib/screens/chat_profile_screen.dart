import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social/providers/auth_provider.dart';
import 'package:social/providers/chat_provider.dart';
import 'package:social/widgets/chat_stats_linear.dart';
import 'package:social/widgets/my_alert_dialog.dart';

class ChatProfileScreen extends ConsumerWidget {
  const ChatProfileScreen({super.key, required this.receiverId});
  final String receiverId;

  void block(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => MyAlertDialog(
        content: 'Are you sure you wan to block this user?',
        title: 'Block',
        text: 'block',
        onpressed: () {
          try {
            ref.read(chatServiceProvider).blockUser(receiverId);
            if (!context.mounted) return;
            context.pop();
            context.pop();

            // show snackbar
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('User blocked!'),
                duration: const Duration(seconds: 2),
              ),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to block user! : $e'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }

  PopupMenuButton<String> showMenuOptions(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'block':
            block(context, ref);
            break;
          case 'star':
            final currentUserId = ref
                .read(authServiceProvider)
                .currentUser!
                .uid;
            final List<String> ids = [currentUserId, receiverId];
            ids.sort();
            final chatRoomId = ids.join('_');
            context.push('/starred/$receiverId', extra: chatRoomId);
            break;
        }
      },
      itemBuilder: (context) {
        return [
          // block
          const PopupMenuItem<String>(
            value: 'block',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block_outlined),
                SizedBox(width: 8),
                Text('Block'),
              ],
            ),
          ),
          const PopupMenuItem<String>(
            value: 'star',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_border),
                SizedBox(width: 8),
                Text('Starred Messages'),
              ],
            ),
          ),
        ];
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userStream = ref.watch(userProfileProvider(receiverId));
    final currentUserId = ref.read(authServiceProvider).currentUser!.uid;
    final chatRoomId = ref
        .read(chatServiceProvider)
        .getChatRoomId(currentUserId, receiverId);
    final mediaAsync = ref.watch(chatMediaProvider(chatRoomId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'User Info',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        actions: [showMenuOptions(context, ref)],
      ),
      body: userStream.when(
        error: (error, stackTrace) => const Center(child: Text('Error:')),
        loading: () => const Center(child: CircularProgressIndicator()),
        data: (userProfile) {
          final userData = userProfile.data() as Map<String, dynamic>?;
          if (userData == null) return const Center(child: Text('No data'));

          final photoUrl = userData['profileImage'];
          final username = userData['username'];
          final about = userData['about'];

          return Padding(
            padding: const EdgeInsets.all(25),
            child: Column(
              children: [
                ClipOval(
                  child: photoUrl != null && photoUrl!.isNotEmpty
                      ? GestureDetector(
                          onTap: () => context.push(
                            '/viewImage',
                            extra: {'photoUrl': photoUrl, 'isProfile': true},
                          ),
                          child: Hero(
                            tag: 'pfp',
                            child: CachedNetworkImage(
                              imageUrl: photoUrl!,
                              height: 120,
                              width: 120,
                              fit: BoxFit.cover,
                              placeholder: (context, url) =>
                                  const CircularProgressIndicator(),
                              errorWidget: (context, url, error) => Icon(
                                Icons.person,
                                size: 50,
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                            ),
                          ),
                        )
                      : CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.secondary,
                          radius: 60,
                          child: Icon(
                            Icons.person,
                            size: 50,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                        ),
                ),
                const SizedBox(height: 10),
                Text(
                  username,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 20),
                Text(about, style: TextStyle(fontSize: 16)),
                SizedBox(height: 40),
                // MEDIA SECTION
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 5,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'MEDIA',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            context.push('/chat_media/$receiverId'),
                        icon: const Icon(Icons.arrow_forward_ios, size: 18),
                      ),
                    ],
                  ),
                ),
                mediaAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, s) => const SizedBox(),
                  data: (mediaDocs) {
                    if (mediaDocs.isEmpty) {
                      return Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            'No media shared',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                          ),
                        ),
                      );
                    }
                    return SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: mediaDocs.length,
                        itemBuilder: (context, index) {
                          final data =
                              mediaDocs[index].data() as Map<String, dynamic>;
                          final isVideo = data['type'] == 'video';
                          final url = isVideo
                              ? data['thumbnailUrl'] as String?
                              : data['message'] as String?;

                          return GestureDetector(
                            onTap: () {
                              // Universal Media Viewer Logic
                              final galleryItems = mediaDocs.map((doc) {
                                final d = doc.data() as Map<String, dynamic>;
                                return {
                                  ...d,
                                  'senderID': d['senderID'] ?? '',
                                  'senderName': d['senderName'] ?? '',
                                };
                              }).toList();

                              context.push(
                                '/media_gallery',
                                extra: {
                                  'mediaMessages': galleryItems,
                                  'initialIndex': index,
                                },
                              );
                            },
                            child: Container(
                              width: 100,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Theme.of(context).colorScheme.surface,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (url != null)
                                      CachedNetworkImage(
                                        imageUrl: url,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) =>
                                            Container(color: Colors.grey[300]),
                                        errorWidget: (_, __, ___) =>
                                            const Icon(Icons.broken_image),
                                      ),
                                    if (isVideo)
                                      const Center(
                                        child: Icon(
                                          Icons.play_arrow,
                                          color: Colors.white,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 30),
                ChatStatsLinear(
                  chatRoomId: ref
                      .read(chatServiceProvider)
                      .getChatRoomId(
                        ref.read(authServiceProvider).currentUser!.uid,
                        receiverId,
                      ),
                  receiverName: username,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
