import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social/providers/auth_provider.dart';
import 'package:social/providers/chat_provider.dart';
import 'package:social/utils/date_utils.dart';
import 'package:social/widgets/chat_bubble.dart';

class StarredMessagesScreen extends ConsumerWidget {
  final String? chatRoomId;
  final String receiverId;
  const StarredMessagesScreen({
    super.key,
    this.chatRoomId,
    required this.receiverId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starredAsync = ref.watch(starredMessagesProvider);
    final currentUserId = ref.watch(authServiceProvider).currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Starred Messages')),
      body: starredAsync.when(
        error: (error, stack) => Center(child: Text('Error: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
        data: (snapshot) {
          var docs = snapshot.docs;

          // Filter if chatRoomId is provided
          if (chatRoomId != null) {
            docs = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['originalChatRoomId'] == chatRoomId;
            }).toList();
          }

          if (docs.isEmpty) {
            return const Center(child: Text('No starred messages'));
          }

          return ListView.builder(
            itemCount: docs.length,
            padding: const EdgeInsets.all(10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final messageId = doc.id;

              final senderID = data['senderID'] as String?;
              final receiverID = data['receiverId'] as String?;

              if (senderID == null || receiverID == null) {
                return const SizedBox.shrink();
              }

              bool isSender = senderID == currentUserId;
              String otherUserId = isSender ? receiverID : senderID;

              // Align based on sender
              var alignment = isSender
                  ? Alignment.centerRight
                  : Alignment.centerLeft;
              var bubbleColor = isSender ? Colors.purpleAccent : Colors.grey;
              final name = isSender ? 'You' : (data['senderName'] ?? 'User');

              final Timestamp timestamp = data['timestamp'];
              final DateTime dateTime = timestamp.toDate();
              final time = DateUtil.getDateLabel(dateTime);

              return InkWell(
                child: Container(
                  margin: EdgeInsets.only(bottom: 10),
                  padding: EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    children: [
                      _MessageHeader(userId: senderID, name: name, time: time),
                      SizedBox(height: 5),
                      ChatBubble(
                        senderName: name,
                        messageId: messageId,
                        userId: senderID,
                        alignment: alignment,
                        isSender: isSender,
                        data: data,
                        bubbleColor: bubbleColor,
                        receiverId: otherUserId,
                        isStarred: true,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MessageHeader extends ConsumerWidget {
  final String userId;
  final String name;
  final String time;

  const _MessageHeader({
    required this.userId,
    required this.name,
    required this.time,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider(userId));

    return userAsync.when(
      data: (snapshot) {
        final data = snapshot.data() as Map<String, dynamic>?;
        final photoUrl = data?['profileImage'];

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ClipOval(
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photoUrl,
                      height: 40,
                      width: 40,
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
                      radius: 20,
                      child: Icon(
                        Icons.person,
                        size: 18,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
            ),
            Text(name),
            Text(time),
          ],
        );
      },
      loading: () => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.surface,
            radius: 20,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
          Text(name),
          Text(time),
        ],
      ),
      error: (error, stack) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.surface,
            radius: 20,
            child: const Icon(Icons.error),
          ),
          Text(name),
          Text(time),
        ],
      ),
    );
  }
}
