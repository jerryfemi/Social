import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:social/providers/chat_provider.dart';

class ChatMediaScreen extends ConsumerWidget {
  final String receiverId;

  const ChatMediaScreen({super.key, required this.receiverId});

  // Helper to get chat room ID
  String _getChatRoomId(String userId1, String userId2) {
    final ids = [userId1, userId2]..sort();
    return ids.join('_');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get current user ID from Firebase Auth
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    // Handle case where user is not logged in
    if (currentUserId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Media')),
        body: const Center(child: Text('User not logged in')),
      );
    }

    final chatRoomId = _getChatRoomId(currentUserId, receiverId);
    final mediaAsync = ref.watch(chatMediaProvider(chatRoomId));

    return Scaffold(
      appBar: AppBar(title: const Text('Media')),
      body: mediaAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
        data: (mediaDocs) {
          if (mediaDocs.isEmpty) {
            return const Center(child: Text('No media found'));
          }

          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: mediaDocs.length,
            itemBuilder: (context, index) {
              final data = mediaDocs[index].data() as Map<String, dynamic>;
              final isVideo = data['type'] == 'video';
              final url = data['type'] == 'image'
                  ? data['message'] as String?
                  : data['thumbnailUrl'] as String?;

              return GestureDetector(
                onTap: () {
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: url != null && url.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.cover,
                              placeholder: (context, url) =>
                                  Container(color: Colors.grey[300]),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[300],
                                child: const Icon(Icons.broken_image),
                              ),
                            )
                          : Container(
                              color: Colors.grey[300],
                              child: const Icon(Icons.broken_image),
                            ),
                    ),
                    // Video indicator
                    if (isVideo)
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
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
              );
            },
          );
        },
      ),
    );
  }
}
