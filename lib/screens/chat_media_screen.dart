import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Add this import

class ChatMediaScreen extends StatelessWidget {
  final String receiverId;

  const ChatMediaScreen({super.key, required this.receiverId});

  // Helper to get chat room ID
  String _getChatRoomId(String userId1, String userId2) {
    final ids = [userId1, userId2]..sort();
    return ids.join('_');
  }

  @override
  Widget build(BuildContext context) {
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

    return Scaffold(
      appBar: AppBar(title: const Text('Media')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('Chat_rooms')
            .doc(chatRoomId)
            .collection('Messages')
            .where('type', whereIn: ['image', 'video'])
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            print('ERROR in StreamBuilder: ${snapshot.error}');

            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No media found'));
          }

          final mediaDocs = snapshot.data!.docs;

          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
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
                  if (isVideo) {
                    context.push(
                      '/videoPlayer',
                      extra: {
                        'videoUrl': data['message'],
                        'caption': data['caption'],
                      },
                    );
                  } else {
                    context.push(
                      '/viewImage',
                      extra: {
                        'photoUrl': data['message'],
                        'caption': data['caption'],
                        'isProfile': false,
                      },
                    );
                  }
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
