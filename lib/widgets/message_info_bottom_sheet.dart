import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MessageInfoBottomSheet extends StatefulWidget {
  final String chatRoomId;
  final String messageId;
  final bool isGroup;

  const MessageInfoBottomSheet({
    super.key,
    required this.chatRoomId,
    required this.messageId,
    required this.isGroup,
  });

  @override
  State<MessageInfoBottomSheet> createState() => _MessageInfoBottomSheetState();
}

class _MessageInfoBottomSheetState extends State<MessageInfoBottomSheet> {
  late Future<DocumentSnapshot> _messageFuture;

  @override
  void initState() {
    super.initState();
    _messageFuture = _fetchMessageDetails();
  }

  Future<DocumentSnapshot> _fetchMessageDetails() {
    return FirebaseFirestore.instance
        .collection('Chat_rooms')
        .doc(widget.chatRoomId)
        .collection('Messages')
        .doc(widget.messageId)
        .get();
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '--';
    return DateFormat('hh:mm a').format(timestamp.toDate());
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '';
    return DateFormat.yMMMd().format(timestamp.toDate());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      padding: const EdgeInsets.only(top: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Message Info',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          Expanded(
            child: FutureBuilder<DocumentSnapshot>(
              future: _messageFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: Text('Message not found.'));
                }

                final data = snapshot.data!.data() as Map<String, dynamic>;
                final status = data['status'] ?? 'sent';
                final timestamp = data['timestamp'] as Timestamp?;

                // Group Data
                final readBy = data['readBy'] as Map<String, dynamic>? ?? {};
                final deliveredTo =
                    data['deliveredTo'] as Map<String, dynamic>? ?? {};

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // MESSAGE CONTENT PREVIEW
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['message'] ??
                                (data['type'] == 'image' ? 'Image' : 'Media'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              '${_formatDate(timestamp)} at ${_formatTime(timestamp)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // STATUS TIMELINE (1-on-1 style, or summary)
                    if (!widget.isGroup) ...[
                      _buildStatusTile(
                        icon: Icons.done,
                        color: Colors.grey,
                        title: 'Sent',
                        time: _formatTime(timestamp),
                      ),
                      // Hide Delivered row if Status is Read
                      if (status != 'read')
                        _buildStatusTile(
                          icon: Icons.done_all,
                          color: (status == 'delivered')
                              ? Colors.blue
                              : Colors.grey,
                          title: 'Delivered',
                          time: status == 'sent' ? '--' : 'Delivered',
                        ),
                      _buildStatusTile(
                        icon: Icons.done_all,
                        color: status == 'read' ? Colors.blue : Colors.grey,
                        title: 'Read',
                        time: status == 'read' ? 'Read' : '--',
                      ),
                    ] else ...[
                      // GROUP STATUS LIST
                      _buildSectionHeader('Read by'),
                      if (readBy.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(left: 16, bottom: 16),
                          child: Text(
                            'No one yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ...readBy.entries
                          .where(
                            (e) =>
                                e.key != FirebaseAuth.instance.currentUser?.uid,
                          )
                          .map((e) {
                            return _buildGroupMemberTile(
                              e.key,
                              e.value,
                              isRead: true,
                            );
                          }),

                      _buildSectionHeader('Delivered to'),
                      if (deliveredTo.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 16, bottom: 16),
                          child: Text(
                            readBy.isNotEmpty
                                ? 'Everyone read it'
                                : 'No one yet',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      ...deliveredTo.entries
                          .where(
                            (e) =>
                                e.key != FirebaseAuth.instance.currentUser?.uid,
                          )
                          .map((e) {
                            // Don't show in delivered if already in read
                            if (readBy.containsKey(e.key)) {
                              return const SizedBox.shrink();
                            }
                            return _buildGroupMemberTile(
                              e.key,
                              e.value,
                              isRead: false,
                            );
                          }),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildStatusTile({
    required IconData icon,
    required Color color,
    required String title,
    required String time,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 16),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(time, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildGroupMemberTile(
    String userId,
    Timestamp timestamp, {
    required bool isRead,
  }) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('Users').doc(userId).get(),
      builder: (context, snapshot) {
        String name = 'Unknown User';
        String? photoUrl;

        if (snapshot.hasData && snapshot.data!.exists) {
          final user = snapshot.data!.data() as Map<String, dynamic>;
          name = user['username'] ?? 'User';
          photoUrl = user['profileImage'];
        }

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: Colors.grey[200],
            backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                ? NetworkImage(photoUrl)
                : null,
            child: photoUrl == null
                ? const Icon(Icons.person, color: Colors.grey)
                : null,
          ),
          title: Text(name),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatTime(timestamp),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Icon(
                isRead ? Icons.done_all : Icons.done,
                size: 16,
                color: isRead ? Colors.blue : Colors.grey,
              ),
            ],
          ),
        );
      },
    );
  }
}
