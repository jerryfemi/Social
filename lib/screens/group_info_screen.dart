import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social/providers/auth_provider.dart';

/// Provider to get group info from Firestore
final groupInfoProvider = StreamProvider.family<DocumentSnapshot, String>((
  ref,
  groupId,
) {
  return FirebaseFirestore.instance
      .collection('Chat_rooms')
      .doc(groupId)
      .snapshots();
});

/// Provider to get group media (images & videos)
/// Note: We fetch all messages and filter locally to avoid Firestore composite index requirement
final groupMediaProvider =
    StreamProvider.family<List<QueryDocumentSnapshot>, String>((ref, groupId) {
      return FirebaseFirestore.instance
          .collection('Chat_rooms')
          .doc(groupId)
          .collection('Messages')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .map((snapshot) {
            // Filter to only media types locally
            return snapshot.docs
                .where((doc) {
                  final type = doc.data()['type'] as String?;
                  return type == 'image' || type == 'video';
                })
                .take(10) // Limit to 10 for preview
                .toList();
          });
    });

class GroupInfoScreen extends ConsumerWidget {
  final String groupId;
  final String? photoUrl;

  const GroupInfoScreen({super.key, required this.groupId, this.photoUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupInfoProvider(groupId));
    final mediaAsync = ref.watch(groupMediaProvider(groupId));
    final currentUserId = ref.read(authServiceProvider).currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Group Info',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      body: groupAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
        data: (groupDoc) {
          if (!groupDoc.exists) {
            return const Center(child: Text('Group not found'));
          }

          final data = groupDoc.data() as Map<String, dynamic>;
          final groupName = data['groupName'] ?? 'Unnamed Group';
          final groupPhoto = data['groupPhotoUrl'] as String?;
          final description = data['groupDescription'] ?? '';
          final participants = List<String>.from(data['participants'] ?? []);
          final adminId = data['adminId'] as String?;
          final isAdmin = adminId == currentUserId;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // GROUP PHOTO
                GestureDetector(
                  onTap: groupPhoto != null && groupPhoto.isNotEmpty
                      ? () => context.push(
                          '/viewImage',
                          extra: {'photoUrl': groupPhoto, 'isProfile': true},
                        )
                      : null,
                  child: ClipOval(
                    child: groupPhoto != null && groupPhoto.isNotEmpty
                        ? Hero(
                            tag: 'group_pfp',
                            child: CachedNetworkImage(
                              imageUrl: groupPhoto,
                              height: 120,
                              width: 120,
                              fit: BoxFit.cover,
                              placeholder: (context, url) =>
                                  const CircularProgressIndicator(),
                              errorWidget: (context, url, error) =>
                                  CircleAvatar(
                                    radius: 60,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.secondary,
                                    child: Icon(
                                      Icons.group,
                                      size: 50,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.tertiary,
                                    ),
                                  ),
                            ),
                          )
                        : CircleAvatar(
                            radius: 60,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.secondary,
                            child: Icon(
                              Icons.group,
                              size: 50,
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                // GROUP NAME
                Text(
                  groupName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
                Text(
                  '${participants.length} members',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 20),

                // ABOUT SECTION
                if (description.isNotEmpty) ...[
                  _buildSectionHeader(context, 'About'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      description,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // MEDIA SECTION
                _buildSectionHeader(
                  context,
                  'Media',
                  trailing: IconButton(
                    onPressed: () => context.push('/group_media/$groupId'),
                    icon: const Icon(Icons.arrow_forward_ios, size: 18),
                  ),
                ),
                mediaAsync.when(
                  loading: () => const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, stack) => const SizedBox(
                    height: 100,
                    child: Center(child: Text('Error loading media')),
                  ),
                  data: (mediaDocs) {
                    if (mediaDocs.isEmpty) {
                      return Container(
                        height: 100,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            'No media yet',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.5),
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
                          final mediaData =
                              mediaDocs[index].data() as Map<String, dynamic>;
                          final isVideo = mediaData['type'] == 'video';
                          final url = isVideo
                              ? mediaData['thumbnailUrl'] as String?
                              : mediaData['message'] as String?;

                          return GestureDetector(
                            onTap: () {
                              if (isVideo) {
                                context.push(
                                  '/videoPlayer',
                                  extra: {
                                    'videoUrl': mediaData['message'],
                                    'caption': mediaData['caption'],
                                    'thumbnailUrl': mediaData['thumbnailUrl'],
                                  },
                                );
                              } else {
                                context.push(
                                  '/viewImage',
                                  extra: {
                                    'photoUrl': url,
                                    'caption': mediaData['caption'],
                                  },
                                );
                              }
                            },
                            child: Container(
                              width: 100,
                              height: 100,
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
                                        placeholder: (context, url) =>
                                            const Center(
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                        errorWidget: (context, url, error) =>
                                            const Icon(Icons.broken_image),
                                      )
                                    else
                                      const Icon(Icons.broken_image),
                                    if (isVideo)
                                      Center(
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.5,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.play_arrow,
                                            color: Colors.white,
                                            size: 20,
                                          ),
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
                const SizedBox(height: 20),

                // MEMBERS SECTION
                _buildSectionHeader(
                  context,
                  'Members (${participants.length})',
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: participants.map((memberId) {
                      return _MemberTile(
                        memberId: memberId,
                        isAdmin: memberId == adminId,
                        isCurrentUser: memberId == currentUserId,
                        canRemove: isAdmin && memberId != currentUserId,
                        groupId: groupId,
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),

                // LEAVE GROUP BUTTON
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showLeaveGroupDialog(context, ref),
                    icon: const Icon(Icons.exit_to_app, color: Colors.red),
                    label: const Text(
                      'Leave Group',
                      style: TextStyle(color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  void _showLeaveGroupDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final currentUserId = ref
                  .read(authServiceProvider)
                  .currentUser!
                  .uid;
              try {
                await FirebaseFirestore.instance
                    .collection('Chat_rooms')
                    .doc(groupId)
                    .update({
                      'participants': FieldValue.arrayRemove([currentUserId]),
                    });
                if (context.mounted) {
                  Navigator.pop(context); // Close dialog
                  context.go('/home'); // Go to home
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('You left the group')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to leave group: $e')),
                  );
                }
              }
            },
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

/// A thinner member tile for the members list
class _MemberTile extends ConsumerWidget {
  final String memberId;
  final bool isAdmin;
  final bool isCurrentUser;
  final bool canRemove;
  final String groupId;

  const _MemberTile({
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
