import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class UserTile extends StatelessWidget {
  final String text;
  final String? photourl;
  final Widget? subtitle;
  final Widget? trailing;
  final void Function()? onTap;
  final void Function()? onLongPress;
  final bool isGroup;
  const UserTile({
    super.key,
    required this.onTap,
    this.onLongPress,
    required this.text,
    this.photourl,
    this.subtitle,
    this.trailing,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: EdgeInsets.only(top: 3),
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(),
        child: Row(
          children: [
            // profile photo
            ClipOval(
              child: photourl != null && photourl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photourl!,
                      width: 66,
                      height: 66,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          const CircularProgressIndicator(),
                      errorWidget: (context, url, error) => Icon(
                        isGroup ? Icons.group : Icons.person,
                        size: 30,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    )
                  : CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      radius: 33,
                      child: Icon(
                        isGroup ? Icons.group : Icons.person,
                        size: 30,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (subtitle != null) subtitle!,
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class MyTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final Widget? trailing;
  final void Function()? ontap;
  const MyTile({
    super.key,
    this.leading,
    required this.title,
    this.trailing,
    this.ontap,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 3),
      padding: EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: leading,
        title: Text(title),
        trailing: trailing,
        onTap: ontap,
      ),
    );
  }
}

class MemberTile extends ConsumerWidget {
  final String memberId;
  final bool isAdmin;
  final bool isCurrentUser;
  final bool canRemove;
  final String groupId;

  const MemberTile({
    super.key,
    required this.memberId,
    required this.isAdmin,
    required this.isCurrentUser,
    required this.canRemove,
    required this.groupId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Users')
          .doc(memberId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final username = userData['username'] ?? 'Unknown';
        final photoUrl = userData['profileImage'] as String?;

        return InkWell(
          onTap: isCurrentUser
              ? null
              : () => context.push('/chat_profile/$memberId'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Profile photo (smaller)
                ClipOval(
                  child: photoUrl != null && photoUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: photoUrl,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => CircleAvatar(
                            radius: 22,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.secondary,
                          ),
                          errorWidget: (context, url, error) => CircleAvatar(
                            radius: 22,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.secondary,
                            child: const Icon(Icons.person, size: 20),
                          ),
                        )
                      : CircleAvatar(
                          radius: 22,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.secondary,
                          child: Icon(
                            Icons.person,
                            size: 20,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                        ),
                ),
                const SizedBox(width: 12),

                // Name & badges
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              isCurrentUser ? 'You' : username,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isAdmin) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Admin',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Remove button (for admin only)
                if (canRemove)
                  IconButton(
                    onPressed: () => _removeMember(context, ref),
                    icon: Icon(
                      Icons.remove_circle_outline,
                      color: Colors.red.withValues(alpha: 0.7),
                      size: 22,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _removeMember(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: const Text(
          'Are you sure you want to remove this member from the group?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection('Chat_rooms')
                    .doc(groupId)
                    .update({
                      'participants': FieldValue.arrayRemove([memberId]),
                    });
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Member removed')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to remove member: $e')),
                  );
                }
              }
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
