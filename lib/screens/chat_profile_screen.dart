import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social/providers/auth_provider.dart';
import 'package:social/providers/chat_provider.dart';
import 'package:social/widgets/my_alert_dialog.dart';
import 'package:social/widgets/user_tile.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userStream = ref.watch(userProfileProvider(receiverId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'User Info',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      body: userStream.when(
        error: (error, stackTrace) => const Center(child: Text('Error:')),
        loading: () => const Center(child: CircularProgressIndicator()),
        data: (userProfile) {
          final userData = userProfile.data() as Map<String, dynamic>?;
          if (userData == null) return const Center(child: Text('No data'));

          final photoUrl = userData['profileImage'];
          final uid = userData['uid'];
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
                SizedBox(height: 70),
                MyTile(title: 'Media'),
                MyTile(
                  title: 'Starred Messages',
                  ontap: () {
                    final currentUserId = ref
                        .read(authServiceProvider)
                        .currentUser!
                        .uid;
                    final List<String> ids = [currentUserId, receiverId];
                    ids.sort();
                    final chatRoomId = ids.join('_');
                    context.push('/starred/$uid', extra: chatRoomId);
                  },
                ),
                MyTile(title: 'Block', ontap: () => block(context, ref)),
              ],
            ),
          );
        },
      ),
    );
  }
}
