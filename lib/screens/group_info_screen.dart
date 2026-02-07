import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart'; // NEW
import 'package:social/providers/auth_provider.dart';
import 'package:social/providers/chat_provider.dart'; // NEW
import 'package:social/services/storage_service.dart'; // NEW
import 'package:social/widgets/chat_stats_circular.dart';
import 'package:social/widgets/my_alert_dialog.dart';
import 'package:social/widgets/user_tile.dart';

class GroupInfoScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String? photoUrl;

  const GroupInfoScreen({super.key, required this.groupId, this.photoUrl});

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  // Edit State
  final _storageService = StorageService();
  final _imagePicker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupInfoProvider(widget.groupId));
    final mediaAsync = ref.watch(groupMediaProvider(widget.groupId));
    final currentUserId = ref.read(authServiceProvider).currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Group Info',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: () => _showLeaveGroupDialog(context, ref),
            icon: Icon(Icons.logout_outlined),
          ),
        ],
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
                Stack(
                  alignment: Alignment.center,
                  children: [
                    GestureDetector(
                      onTap: groupPhoto != null && groupPhoto.isNotEmpty
                          ? () => context.push(
                              '/viewImage',
                              extra: {
                                'photoUrl': groupPhoto,
                                'isProfile': true,
                              },
                            )
                          : null,
                      child: ClipOval(
                        child: groupPhoto != null && groupPhoto.isNotEmpty
                            ? Hero(
                                tag: 'pfp',
                                child: CachedNetworkImage(
                                  imageUrl: groupPhoto,
                                  height: 120,
                                  width: 120,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) =>
                                      const CircularProgressIndicator(),
                                  errorWidget: (_, __, ___) => CircleAvatar(
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
                    if (isAdmin)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _pickAndUploadImage,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            child: Icon(
                              Icons.edit,
                              size: 16,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // GROUP NAME
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      groupName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                    if (isAdmin)
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _showEditDialog(
                          'Group Name',
                          groupName,
                          (val) => _updateGroup(name: val),
                        ),
                      ),
                  ],
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
                if (description.isNotEmpty || isAdmin) ...[
                  _buildSectionHeader(
                    context,
                    'About',
                    trailing: isAdmin
                        ? IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => _showEditDialog(
                              'Description',
                              description,
                              (val) => _updateGroup(about: val),
                            ),
                          )
                        : null,
                  ),
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
                    onPressed: () =>
                        context.push('/group_media/${widget.groupId}'),
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
                              final galleryItems = mediaDocs.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                // Ensure timestamp is passed for the new header format
                                return {
                                  ...data,
                                  'senderID':
                                      data['senderID'] ?? '', // Fallback
                                  'senderName':
                                      data['senderName'] ?? '', // Fallback
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
                const SizedBox(height: 30),

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
                      return MemberTile(
                        memberId: memberId,
                        isAdmin: memberId == adminId,
                        isCurrentUser: memberId == currentUserId,
                        canRemove: isAdmin && memberId != currentUserId,
                        groupId: widget.groupId,
                      );
                    }).toList(),
                  ),
                ),

                // STATS SECTION
                ChatStatsCircular(groupId: widget.groupId),
                const SizedBox(height: 30),

                if (isAdmin)
                  FilledButton.icon(
                    onPressed: () => _showDeleteGroupDialog(context, ref),
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('Delete Group'),
                  ),

                const SizedBox(height: 20),
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
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // UPDATE GROUP INFO
  Future<void> _updateGroup({
    String? name,
    String? about,
    String? photoUrl,
  }) async {
    // setState(() => _isUpdating = true);
    try {
      await ref
          .read(chatServiceProvider)
          .updateGroupInfo(
            widget.groupId,
            name: name,
            about: about,
            photoUrl: photoUrl,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating group: $e')));
      }
    } finally {
      // if (mounted) setState(() => _isUpdating = false);
    }
  }

  // EDIT DIALOG
  void _showEditDialog(
    String title,
    String initialValue,
    Function(String) onSave,
  ) {
    final controller = TextEditingController(text: initialValue);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit $title'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: 'Enter new $title'),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) {
                onSave(val);
                context.pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // PICK IMAGE
  Future<void> _pickAndUploadImage() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
      );
      if (picked == null) return;

      // setState(() => _isUpdating = true);

      final bytes = await picked.readAsBytes();
      final url = await _storageService.uploadGroupPhoto(
        'group_${widget.groupId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        bytes,
      );

      await _updateGroup(photoUrl: url);
    } catch (e) {
      debugPrint('Error uploading image: $e');
    } finally {
      // if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _showLeaveGroupDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group'),
        content: const Text(
          'Are you sure you want to leave this group? You won\'t be able to see previous messages or send new ones.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(chatServiceProvider).leaveGroup(widget.groupId);
              if (context.mounted) context.go('/home');
            },
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showDeleteGroupDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: const Text(
          'Are you sure you want to delete this group? This action cannot be undone and will remove the group for all members.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(chatServiceProvider).deleteGroup(widget.groupId);
              if (context.mounted) context.go('/home');
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
