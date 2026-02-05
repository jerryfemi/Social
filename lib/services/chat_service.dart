import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:social/models/message_hive.dart';
import 'package:social/services/auth_service.dart';
import 'package:social/services/sound_service.dart';
import 'package:social/services/storage_service.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class ChatService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _auth = AuthService();
  final StorageService _storageService = StorageService();

  // 1. GET RECENT CHATS STREAM ()
  Stream<List<Map<String, dynamic>>> getRecentChats(String currentUserId) {
    return _firestore
        .collection('Chat_rooms')
        .where('participants', arrayContains: currentUserId)
        .orderBy('lastMessageTimestamp', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          List<Map<String, dynamic>> recentChats = [];

          final blockedUsersSnapshot = await _firestore
              .collection('Users')
              .doc(currentUserId)
              .collection('BlockedUsers')
              .get();

          final blockedUsersIds = blockedUsersSnapshot.docs
              .map((doc) => doc.id)
              .toList();

          for (var doc in snapshot.docs) {
            final chatRoomData = doc.data();
            final List participants = chatRoomData['participants'];
            final String? chatType = chatRoomData['type'];

            // Handle GROUP chats
            if (chatType == 'group') {
              recentChats.add({
                'uid': doc.id, // Use chat room ID as uid for groups
                'username': chatRoomData['groupName'] ?? 'Unnamed Group',
                'profileImage': chatRoomData['groupPhotoUrl'],
                'isGroup': true,
                'participants': participants,
                'lastMessage': chatRoomData['lastMessage'] ?? '',
                'lastMessageTimestamp': chatRoomData['lastMessageTimestamp'],
                'lastMessageStatus': chatRoomData['lastMessageStatus'],
                'lastSenderId': chatRoomData['lastSenderId'],
              });
              continue;
            }

            // Handle 1-on-1 chats
            // Find the OTHER user's ID
            String otherUserId = participants.firstWhere(
              (id) => id != currentUserId,
              orElse: () => '',
            );

            // if blocked users id is part of other users id, ignore it
            if (blockedUsersIds.contains(otherUserId)) {
              continue;
            }
            // Fetch that user's profile details
            final userDoc = await _firestore
                .collection('Users')
                .doc(otherUserId)
                .get();

            if (!userDoc.exists) continue;

            final userData = userDoc.data() as Map<String, dynamic>;

            // Combine User Data with Chat Room Data (for last message info)
            recentChats.add({
              ...userData, // username, profileImage, etc.
              'isGroup': false,
              'lastMessage': chatRoomData['lastMessage'] ?? '',
              'lastMessageTimestamp': chatRoomData['lastMessageTimestamp'],
              'lastMessageStatus': chatRoomData['lastMessageStatus'],
              'lastSenderId': chatRoomData['lastSenderId'],
            });
          }
          return recentChats;
        });
  }

  // 1b. SEARCH/FILTER RECENT CHATS (Local filtering - instant, works offline)
  /// Filters an already-loaded list of recent chats by username or last message.
  /// Use this in your UI to filter the chat list as user types.
  List<Map<String, dynamic>> filterRecentChats(
    List<Map<String, dynamic>> recentChats,
    String query,
  ) {
    if (query.isEmpty) return recentChats;

    final lowerQuery = query.toLowerCase();

    return recentChats.where((chat) {
      final username = (chat['username'] ?? '').toString().toLowerCase();
      final lastMessage = (chat['lastMessage'] ?? '').toString().toLowerCase();

      return username.contains(lowerQuery) || lastMessage.contains(lowerQuery);
    }).toList();
  }

  // 2. SEARCH USERS STREAM
  Stream<List<Map<String, dynamic>>> searchUsers(String query) {
    if (query.isEmpty) return Stream.value([]);

    // search users in lowercase.
    String lowercaseQuery = query.toLowerCase();

    return _firestore
        .collection('Users')
        .where('searchKey', isGreaterThanOrEqualTo: lowercaseQuery)
        .where('searchKey', isLessThan: '$lowercaseQuery/uf8ff')
        .snapshots()
        .asyncMap((snapshot) async {
          final currentUserId = _auth.currentUser!.uid;

          // get blocked users firestore
          final blockedSnapshot = await _firestore
              .collection('Users')
              .doc(currentUserId)
              .collection('BlockedUsers')
              .get();

          // get blocked users id
          final List<String> blockedUserIds = blockedSnapshot.docs
              .map((doc) => doc.id)
              .toList();

          return snapshot.docs
              .where((doc) {
                final data = doc.data();
                final userId = data['uid'];

                // exclude self and blocked users
                return data['email'] != _auth.currentUser!.email &&
                    !blockedUserIds.contains(userId);
              })
              .map((doc) => doc.data())
              .toList();
        });
  }

  // send message
  Future<void> sendMessage(
    String receiverID,
    String message, {
    String? localId,
    String? replyToId,
    String? replyToMessage,
    String? replyToSender,
    String? replyToType,
    String type = 'text',
    String? caption,
    bool isGroup = false,
  }) async {
    final String currentUserID = _auth.currentUser!.uid;
    final String currentUserEmail = _auth.currentUser!.email!;
    final Timestamp timestamp = Timestamp.now();

    DocumentSnapshot userDoc = await _firestore
        .collection('Users')
        .doc(currentUserID)
        .get();

    String username = userDoc['username'];

    // create a new message
    Message newMessage = Message(
      senderID: currentUserID,
      senderEmail: currentUserEmail,
      receiverID: receiverID,
      message: message,
      timestamp: timestamp.toDate(),
      localId: localId ?? const Uuid().v4(),
      senderName: username,
      status: MessageStatus.sent,
      type: type,
      caption: caption,
      replyToId: replyToId,
      replyToMessage: replyToMessage,
      replyToSender: replyToSender,
      replyToType: replyToType,
    );

    // construct chat room ID - for groups, receiverID is the groupId
    String chatRoomID;
    if (isGroup) {
      chatRoomID = receiverID;
    } else {
      List<String> ids = [currentUserID, receiverID];
      ids.sort();
      chatRoomID = ids.join('_');
    }

    // Prepare message data - add group tracking fields if it's a group
    final messageData = newMessage.toFirestoreMap();
    if (isGroup) {
      // For groups, track who has read/delivered the message
      // Sender automatically has "read" their own message
      messageData['readBy'] = {currentUserID: timestamp};
      messageData['deliveredTo'] = {currentUserID: timestamp};
    }

    // add new message to database
    await _firestore
        .collection('Chat_rooms')
        .doc(chatRoomID)
        .collection("Messages")
        .add(messageData);

    await _firestore
        .collection('Chat_rooms')
        .doc(chatRoomID)
        .collection('Messages')
        .doc()
        .set({});

    // Determine last message text
    String lastMsg = message;
    if (type == 'image') {
      lastMsg = caption ?? '📷 Photo';
      if (message.contains('giphy') || type == 'image') {
        lastMsg = caption ?? 'GIF';
      }
    } else if (type == 'video') {
      lastMsg = caption ?? '🎥 Video';
    }

    // Update chat room metadata
    final chatRoomUpdate = <String, dynamic>{
      'lastMessage': lastMsg,
      'lastMessageTimestamp': timestamp,
      'lastMessageStatus': 'sent',
      'lastSenderId': currentUserID,
    };

    // Only set participants for 1-on-1 chats (groups already have participants)
    if (!isGroup) {
      chatRoomUpdate['participants'] = [currentUserID, receiverID];
    }

    await _firestore
        .collection('Chat_rooms')
        .doc(chatRoomID)
        .set(chatRoomUpdate, SetOptions(merge: true));

    // Play send sound on successful upload
    SoundService().playSend();
  }

  // get message
  Stream<QuerySnapshot> getMessages(String userID, String otherUserID) {
    // chat room ID for the two users
    List<String> ids = [userID, otherUserID];
    ids.sort();
    final chatRoomID = ids.join('_');

    return _firestore
        .collection('Chat_rooms')
        .doc(chatRoomID)
        .collection('Messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  // listen for inoming Messages.
  StreamSubscription<QuerySnapshot> listenToIncomingMessages(
    String currentUserId,
  ) {
    return _firestore
        .collectionGroup('Messages')
        .where('receiverId', isEqualTo: currentUserId)
        .where('status', isEqualTo: MessageStatus.sent)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.docs.isNotEmpty) {
            final batch = _firestore.batch();
            for (var doc in snapshot.docs) {
              batch.update(doc.reference, {'status': MessageStatus.delivered});

              if (doc.reference.parent.parent != null) {
                batch.update(doc.reference.parent.parent!, {
                  'lastMessageStatus': MessageStatus.delivered,
                });
              }
            }

            batch.commit();
            debugPrint("Delivered ${snapshot.docs.length} messages globally.");
          }
        });
  }

  // mark message as read
  Future<void> messageRead(String currentUserId, String receiverId) async {
    // chat room id for the two users
    List<String> ids = [currentUserId, receiverId];
    ids.sort();
    final chatRoomID = ids.join('_');

    final chatRoomDoc = await _firestore
        .collection('Chat_rooms')
        .doc(chatRoomID)
        .get();

    if (!chatRoomDoc.exists) return;
    final data = chatRoomDoc.data() as Map<String, dynamic>;
    final lastSenderId = data['lastSenderId'];
    final unreadMessages = await _firestore
        .collection('Chat_rooms')
        .doc(chatRoomID)
        .collection('Messages')
        .where('receiverId', isEqualTo: currentUserId)
        .where('status', isNotEqualTo: MessageStatus.read)
        .get();

    if (unreadMessages.docs.isEmpty) return;

    final batch = _firestore.batch();

    // Mark all individual messages as read
    for (var doc in unreadMessages.docs) {
      batch.update(doc.reference, {'status': MessageStatus.read});
    }

    // UPDATE THE LAST MESSAGE STATUS to read.
    if (lastSenderId == receiverId) {
      final chatRoomRef = _firestore.collection('Chat_rooms').doc(chatRoomID);
      batch.update(chatRoomRef, {'lastMessageStatus': MessageStatus.read});
    }

    await batch.commit();
  }

  /// Mark group messages as read by the current user
  /// This updates the `readBy` map on each unread message
  Future<void> markGroupMessagesAsRead(String groupId) async {
    final currentUserId = _auth.currentUser!.uid;
    final timestamp = Timestamp.now();

    try {
      // Get all messages not read by current user
      // We get all messages and filter locally since complex queries need indexes
      final messagesSnapshot = await _firestore
          .collection('Chat_rooms')
          .doc(groupId)
          .collection('Messages')
          .orderBy('timestamp', descending: true)
          .limit(50) // Only process recent messages
          .get();

      if (messagesSnapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      int updatedCount = 0;

      for (final doc in messagesSnapshot.docs) {
        final data = doc.data();
        final senderId = data['senderID'] as String?;

        // Skip messages sent by current user
        if (senderId == currentUserId) continue;

        // Check if already read by current user
        final readBy = data['readBy'] as Map<String, dynamic>? ?? {};
        if (readBy.containsKey(currentUserId)) continue;

        // Mark as read by adding to readBy map
        batch.update(doc.reference, {
          'readBy.$currentUserId': timestamp,
          'deliveredTo.$currentUserId': timestamp, // Also mark as delivered
        });
        updatedCount++;
      }

      if (updatedCount > 0) {
        // Update the last message status in chat room
        final groupDoc = await _firestore
            .collection('Chat_rooms')
            .doc(groupId)
            .get();
        if (groupDoc.exists) {
          final data = groupDoc.data()!;
          final lastSenderId = data['lastSenderId'] as String?;
          // Only update lastMessageStatus if current user didn't send the last message
          if (lastSenderId != currentUserId) {
            batch.update(groupDoc.reference, {
              'lastMessageStatus': MessageStatus.read,
            });
          }
        }

        await batch.commit();
        debugPrint('✅ Marked $updatedCount group messages as read');
      }
    } catch (e) {
      debugPrint('❌ Error marking group messages as read: $e');
    }
  }

  /// Calculate group message status based on readBy/deliveredTo maps
  /// Returns 'read', 'delivered', or 'sent'
  static String calculateGroupMessageStatus(
    Map<String, dynamic> messageData,
    List<String> participants,
    String senderId,
  ) {
    // Get other participants (exclude sender)
    final otherParticipants = participants.where((p) => p != senderId).toList();
    if (otherParticipants.isEmpty) return MessageStatus.sent;

    final readBy = messageData['readBy'] as Map<String, dynamic>? ?? {};
    final deliveredTo =
        messageData['deliveredTo'] as Map<String, dynamic>? ?? {};

    // Check if all other participants have read
    final allRead = otherParticipants.every((p) => readBy.containsKey(p));
    if (allRead) return MessageStatus.read;

    // Check if all other participants have received
    final allDelivered = otherParticipants.every(
      (p) => deliveredTo.containsKey(p),
    );
    if (allDelivered) return MessageStatus.delivered;

    return MessageStatus.sent;
  }

  // report user
  Future<void> reportUser(String messageId, String userId) async {
    final currentUser = _auth.currentUser;
    final report = {
      'reportedBy': currentUser!.uid,
      'messageId': messageId,
      'messageOwnerId': userId,
      'timestamp': FieldValue.serverTimestamp(),
    };
    await _firestore.collection('Reports').add(report);
  }

  // block user
  Future<void> blockUser(String userId) async {
    final currentUser = _auth.currentUser;
    await _firestore
        .collection('Users')
        .doc(currentUser!.uid)
        .collection('BlockedUsers')
        .doc(userId)
        .set({
          'blockedBy': currentUser.uid,
          'timestamp': FieldValue.serverTimestamp(),
        });

    notifyListeners();
  }

  // unblock user
  Future<void> unblockUser(String blockedUserId) async {
    final currentUser = _auth.currentUser;
    await _firestore
        .collection('Users')
        .doc(currentUser!.uid)
        .collection('BlockedUsers')
        .doc(blockedUserId)
        .delete();
    notifyListeners();
  }

  // edit message
  Future<void> editMessage(
    String otherUserId,
    String messageId,
    String newMessage,
  ) async {
    final currentUserId = _auth.currentUser!.uid;
    List<String> ids = [currentUserId, otherUserId];
    ids.sort();
    final chatRoomId = ids.join('_');

    final messageRef = _firestore
        .collection('Chat_rooms')
        .doc(chatRoomId)
        .collection('Messages')
        .doc(messageId);

    // Get message to verify ownership
    final docSnapshot = await messageRef.get();
    if (!docSnapshot.exists) return;

    final data = docSnapshot.data() as Map<String, dynamic>;
    final String senderId = data['senderID'];

    // Only allow editing own messages
    if (senderId != currentUserId) return;

    // Update the message with edited content and timestamp
    await messageRef.update({
      'message': newMessage,
      'isEdited': true,
      'editedAt': FieldValue.serverTimestamp(),
    });

    // Update last message in chat room if this was the last message
    final chatRoomRef = _firestore.collection('Chat_rooms').doc(chatRoomId);
    final chatRoomSnapshot = await chatRoomRef.get();

    if (chatRoomSnapshot.exists) {
      final chatRoomData = chatRoomSnapshot.data() as Map<String, dynamic>;
      // Only update if this message's ID matches the last message
      // We check by comparing timestamps
      final Timestamp messageTimestamp = data['timestamp'];
      final Timestamp? lastMessageTimestamp =
          chatRoomData['lastMessageTimestamp'];

      if (lastMessageTimestamp != null &&
          messageTimestamp.millisecondsSinceEpoch ==
              lastMessageTimestamp.millisecondsSinceEpoch) {
        await chatRoomRef.update({'lastMessage': newMessage});
      }
    }
  }

  // delete message
  Future<void> deleteMessage(
    String otherUserId,
    String messageId, {
    bool deleteForEveryone = false,
  }) async {
    final currentUserId = _auth.currentUser!.uid;
    List<String> ids = [currentUserId, otherUserId];
    ids.sort();
    final chatRoomId = ids.join('_');

    final messageRef = _firestore
        .collection('Chat_rooms')
        .doc(chatRoomId)
        .collection('Messages')
        .doc(messageId);

    // Get message to check ownership and timestamp
    final docSnapshot = await messageRef.get();
    if (!docSnapshot.exists) return;

    final data = docSnapshot.data() as Map<String, dynamic>;
    final Timestamp messageTimestamp = data['timestamp'];
    final String senderId = data['senderID'];
    final bool isOwnMessage = senderId == currentUserId;

    // If it's your own message OR deleteForEveryone is true, delete completely
    if (isOwnMessage || deleteForEveryone) {
      await messageRef.delete();

      // Update last message if this was the last message
      await _updateLastMessageAfterDelete(chatRoomId, messageTimestamp);
    } else {
      // If it's someone else's message, hide it only for the current user
      await messageRef.update({
        'deletedFor': FieldValue.arrayUnion([currentUserId]),
      });
    }
  }

  // Helper to update last message after deletion
  Future<void> _updateLastMessageAfterDelete(
    String chatRoomId,
    Timestamp deletedMessageTimestamp,
  ) async {
    final chatRoomRef = _firestore.collection('Chat_rooms').doc(chatRoomId);
    final chatRoomSnapshot = await chatRoomRef.get();

    if (!chatRoomSnapshot.exists) return;

    final chatRoomData = chatRoomSnapshot.data() as Map<String, dynamic>;
    final Timestamp? lastMessageTimestamp =
        chatRoomData['lastMessageTimestamp'];

    // Only update if the deleted message was the last message
    if (lastMessageTimestamp == deletedMessageTimestamp) {
      // Get the new last message
      final messagesSnapshot = await _firestore
          .collection('Chat_rooms')
          .doc(chatRoomId)
          .collection('Messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (messagesSnapshot.docs.isNotEmpty) {
        final newLastMessage = messagesSnapshot.docs.first.data();
        final String type = newLastMessage['type'] ?? 'text';
        String lastMsg;

        if (type == 'image') {
          lastMsg = newLastMessage['caption'] ?? '📷 Photo';
        } else if (type == 'video') {
          lastMsg = newLastMessage['caption'] ?? '🎥 Video';
        } else {
          lastMsg = newLastMessage['message'] ?? '';
        }

        await chatRoomRef.update({
          'lastMessage': lastMsg,
          'lastMessageTimestamp': newLastMessage['timestamp'],
          'lastMessageStatus': newLastMessage['status'],
          'lastSenderId': newLastMessage['senderID'],
        });
      } else {
        // No messages left, clear last message info
        await chatRoomRef.update({
          'lastMessage': '',
          'lastMessageTimestamp': null,
          'lastMessageStatus': null,
          'lastSenderId': null,
        });
      }
    }
  }

  // get blocked users stream
  Stream<List<Map<String, dynamic>>> getblockedUsers(String userId) {
    return _firestore
        .collection('Users')
        .doc(userId)
        .collection('BlockedUsers')
        .snapshots()
        .asyncMap((snapShot) async {
          // get list of blocked user ids
          final blockedUserIds = snapShot.docs.map((doc) => doc.id).toList();

          final userDocs = await Future.wait(
            blockedUserIds.map(
              (id) => _firestore.collection('Users').doc(id).get(),
            ),
          );

          return userDocs
              .map((doc) => doc.data() as Map<String, dynamic>)
              .toList();
        });
  }

  // update TextFields (about and username)
  Future<void> updateUserData(String name, String about) async {
    String uid = _auth.currentUser!.uid;
    await _firestore.collection('Users').doc(uid).update({
      'username': name,
      'about': about,
      'searchKey': name.toLowerCase(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    notifyListeners();
  }

  // update profile photo url
  Future<void> updateUserPhotoUrl(String photoUrl) async {
    String uid = _auth.currentUser!.uid;
    await _firestore.collection('Users').doc(uid).update({
      'profileImage': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    notifyListeners();
  }

  // Get current user data
  Future<DocumentSnapshot> getCurrentUserData() async {
    String uid = _auth.currentUser!.uid;
    return await _firestore.collection('Users').doc(uid).get();
  }

  // get current user stream
  Stream<DocumentSnapshot> getUserStream(String uid) {
    return _firestore.collection('Users').doc(uid).snapshots();
  }

  // send voice message
  Future<void> sendVoiceMessage(
    String receiverID,
    String voicePath,
    int duration, {
    String? replyToId,
    String? replyToMessage,
    String? replyToSender,
    String? localId,
    String? replyToType,
    bool isGroup = false,
  }) async {
    final String currentUserID = _auth.currentUser!.uid;
    final String currentUserEmail = _auth.currentUser!.email!;
    final Timestamp timestamp = Timestamp.now();

    // construct chat room id - for groups, receiverID is the groupId
    String chatRoomID;
    if (isGroup) {
      chatRoomID = receiverID;
    } else {
      List<String> ids = [currentUserID, receiverID];
      ids.sort();
      chatRoomID = ids.join('_');
    }

    // upload voice file to storage
    File voiceFile = File(voicePath);
    String voiceUrl = await _storageService.uploadChatFile(
      chatRoomID,
      'voice_${timestamp.millisecondsSinceEpoch}.m4a',
      file: voiceFile,
    );

    // get sender info
    DocumentSnapshot userDoc = await _firestore
        .collection('Users')
        .doc(currentUserID)
        .get();

    String username = userDoc['username'];

    // send message (type voice)
    Message message = Message(
      senderID: currentUserID,
      senderEmail: currentUserEmail,
      senderName: username,
      receiverID: receiverID,
      status: MessageStatus.sent,
      message: voiceUrl,
      timestamp: timestamp.toDate(),
      type: 'voice',
      voiceDuration: duration,
      replyToId: replyToId,
      replyToMessage: replyToMessage,
      replyToSender: replyToSender,
      replyToType: replyToType,
      localId: localId ?? const Uuid().v4(),
    );

    // Prepare message data - add group tracking fields if it's a group
    final messageData = message.toFirestoreMap();
    if (isGroup) {
      // For groups, track who has read/delivered the message
      messageData['readBy'] = {currentUserID: timestamp};
      messageData['deliveredTo'] = {currentUserID: timestamp};
    }

    // add to firestore
    await _firestore
        .collection('Chat_rooms')
        .doc(chatRoomID)
        .collection('Messages')
        .add(messageData);

    // Update chat room metadata
    final chatRoomUpdate = <String, dynamic>{
      'lastMessage': '🎤 Voice message',
      'lastMessageTimestamp': timestamp,
      'lastMessageStatus': MessageStatus.sent,
      'lastSenderId': currentUserID,
    };

    // Only set participants for 1-on-1 chats (groups already have participants)
    if (!isGroup) {
      chatRoomUpdate['participants'] = [currentUserID, receiverID];
    }

    await _firestore
        .collection('Chat_rooms')
        .doc(chatRoomID)
        .set(chatRoomUpdate, SetOptions(merge: true));

    // Play send sound on successful upload
    SoundService().playSend();
  }

  // send image message
  Future<void> sendMediaMessage(
    String receiverID,
    String fileName, {
    Uint8List? imageBytes,
    String? caption,
    String? videoPath,
    String? localId,
    String? replyToId,
    String? replyToMessage,
    String? replyToSender,
    String? replyToType,
    bool isGroup = false,
  }) async {
    final String currentuserID = _auth.currentUser!.uid;
    final String currentuserEmail = _auth.currentUser!.email!;
    final Timestamp timestamp = Timestamp.now();

    // construct chat room id - for groups, receiverID is the groupId
    String chatRoomID;
    if (isGroup) {
      chatRoomID = receiverID;
    } else {
      List<String> ids = [currentuserID, receiverID];
      ids.sort();
      chatRoomID = ids.join('_');
    }

    String mediaUrl;
    String type;
    String notificationText;
    String? thumbnailUrl;

    if (videoPath != null) {
      // Generate video thumbnail
      try {
        final thumbnailData = await VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 300,
          quality: 75,
        );

        if (thumbnailData != null) {
          // Upload thumbnail to storage
          final thumbnailFileName = 'thumb_$fileName.jpg';
          thumbnailUrl = await _storageService.uploadChatFile(
            chatRoomID,
            thumbnailFileName,
            filebytes: thumbnailData,
          );
        }
      } catch (e) {
        debugPrint('Error generating video thumbnail: $e');
      }

      // upload video to storage
      File videoFile = File(videoPath);
      mediaUrl = await _storageService.uploadChatFile(
        chatRoomID,
        fileName,
        file: videoFile,
      );
      type = 'video';
      notificationText = '🎥 Video';
    } else if (imageBytes != null) {
      // upload images to storage
      mediaUrl = await _storageService.uploadChatFile(
        chatRoomID,
        fileName,
        filebytes: imageBytes,
      );
      type = 'image';
      notificationText = '📷 Photo';
    } else {
      return;
    }

    // get sender info
    DocumentSnapshot userDoc = await _firestore
        .collection('Users')
        .doc(currentuserID)
        .get();

    String username = userDoc['username'];

    // send message (type image)
    Message message = Message(
      senderID: currentuserID,
      senderEmail: currentuserEmail,
      senderName: username,
      receiverID: receiverID,
      message: mediaUrl,
      caption: caption,
      status: MessageStatus.sent,
      localId: localId ?? const Uuid().v4(),
      timestamp: timestamp.toDate(),
      type: type,
      thumbnailUrl: thumbnailUrl,
      replyToId: replyToId,
      replyToMessage: replyToMessage,
      replyToSender: replyToSender,
      replyToType: replyToType,
    );

    // Prepare message data - add group tracking fields if it's a group
    final messageData = message.toFirestoreMap();
    if (isGroup) {
      // For groups, track who has read/delivered the message
      messageData['readBy'] = {currentuserID: timestamp};
      messageData['deliveredTo'] = {currentuserID: timestamp};
    }

    // add to firestore
    await _firestore
        .collection('Chat_rooms')
        .doc(chatRoomID)
        .collection('Messages')
        .add(messageData);

    // update last message
    String lastMsg = caption != null
        ? '$notificationText: $caption'
        : notificationText;

    // Update chat room metadata
    final chatRoomUpdate = <String, dynamic>{
      'lastMessage': lastMsg,
      'lastMessageTimestamp': timestamp,
      'lastMessageStatus': MessageStatus.sent,
      'lastSenderId': currentuserID,
    };

    // Only set participants for 1-on-1 chats (groups already have participants)
    if (!isGroup) {
      chatRoomUpdate['participants'] = [currentuserID, receiverID];
    }

    await _firestore
        .collection('Chat_rooms')
        .doc(chatRoomID)
        .set(chatRoomUpdate, SetOptions(merge: true));

    // Play send sound on successful upload
    SoundService().playSend();
  }

  // Set Chat Wallpaper
  Future<void> setChatWallpaper(
    String receiverID,
    Uint8List fileBytes,
    String fileName,
  ) async {
    final currentUserID = _auth.currentUser!.uid;

    // construct chat room id
    List<String> ids = [currentUserID, receiverID];
    ids.sort();
    String chatRoomId = ids.join('_');

    // upload wallpaper
    String wallpaperUrl = await _storageService.uploadChatFile(
      chatRoomId,
      fileName,
      filebytes: fileBytes,
    );

    // save to chat room document

    await _firestore
        .collection('Chat_rooms')
        .doc(chatRoomId)
        .update({
          'wallpaper': {currentUserID: wallpaperUrl},
        })
        .catchError((e) {
          return _firestore.collection('Chat_rooms').doc(chatRoomId).set({
            'wallpaper': {currentUserID: wallpaperUrl},
          }, SetOptions(merge: true));
        });
  }

  // Set Chat Wallpaper (Solid Color)
  Future<void> setChatWallpaperColor(
    String receiverID,
    String hexColorCode,
  ) async {
    final currentUserID = _auth.currentUser!.uid;

    // Construct chat room ID
    List<String> ids = [currentUserID, receiverID];
    ids.sort();
    String chatRoomId = ids.join('_');

    final chatRoomRef = _firestore.collection('Chat_rooms').doc(chatRoomId);

    final docSnapshot = await chatRoomRef.get();
    if (docSnapshot.exists) {
      final data = docSnapshot.data();
      if (data != null && data.containsKey('wallpaper')) {
        final wallpaperMap = data['wallpaper'] as Map<String, dynamic>;
        final String? oldValue = wallpaperMap[currentUserID];

        // If the old value is a URL (starts with http), delete the file.
        if (oldValue != null && oldValue.startsWith('http')) {
          await _storageService.deleteChatWallpaperFile(oldValue);
        }
      }
    }

    //  SAVE THE COLOR STRING
    await chatRoomRef.set({
      'wallpaper': {currentUserID: hexColorCode},
    }, SetOptions(merge: true));
  }

  // Delete Chat Wallpaper
  Future<void> deleteChatWallpaper(String receiverID) async {
    final currentUserID = _auth.currentUser!.uid;
    List<String> ids = [currentUserID, receiverID];
    ids.sort();
    String chatRoomId = ids.join('_');

    final chatRoomRef = _firestore.collection('Chat_rooms').doc(chatRoomId);
    final chatRoomDoc = await chatRoomRef.get();
    if (!chatRoomDoc.exists) return;
    final data = chatRoomDoc.data();
    if (data == null || !data.containsKey('wallpaper')) return;
    final wallpaperMap = data['wallpaper'] as Map<String, dynamic>?;
    if (wallpaperMap == null || !wallpaperMap.containsKey(currentUserID)) {
      return;
    }
    final wallpaperUrl = wallpaperMap[currentUserID] as String;

    // Remove wallpaper entry for this user
    wallpaperMap.remove(currentUserID);
    await chatRoomRef.update({'wallpaper': wallpaperMap});

    // Delete wallpaper file from storage
    if (wallpaperUrl.startsWith('http')) {
      await _storageService.deleteChatWallpaperFile(wallpaperUrl);
    }
  }

  // Pin Message
  Future<void> pinMessage(String receiverId, Message message) async {
    final currentUserId = _auth.currentUser!.uid;
    List<String> ids = [currentUserId, receiverId];
    ids.sort();
    String chatRoomId = ids.join('_');

    String displayContent = message.message;
    if (message.type == 'image' || message.type == 'video') {
      displayContent =
          message.caption ??
          (message.type == 'video' ? '🎥 Video' : '📷 Photo');
    } else if (message.type == 'voice') {
      displayContent = '🎤 Voice message';
    }

    await _firestore.collection('Chat_rooms').doc(chatRoomId).update({
      'pinnedMessage': {
        'id': message.localId,
        'message': displayContent,
        'originalMessage': message.message,
        'type': message.type,
        'senderId': message.senderID,
        'timestamp': message.timestamp,
      },
    });
  }

  // Unpin Message
  Future<void> unpinMessage(String receiverId) async {
    final currentUserId = _auth.currentUser!.uid;
    List<String> ids = [currentUserId, receiverId];
    ids.sort();
    String chatRoomId = ids.join('_');

    await _firestore.collection('Chat_rooms').doc(chatRoomId).update({
      'pinnedMessage': FieldValue.delete(),
    });
  }

  // get chat stream
  Stream<DocumentSnapshot> getChatStream(String receiverId) {
    final currentUserID = _auth.currentUser!.uid;

    // construct chat room id
    List<String> ids = [currentUserID, receiverId];
    ids.sort();
    String chatRoomID = ids.join('_');

    return _firestore.collection('Chat_rooms').doc(chatRoomID).snapshots();
  }

  // Star  message
  Future<void> toggleStarMessage(
    Map<String, dynamic> messageData,
    String messageId,
    String receiverId,
  ) async {
    final currentUserId = _auth.currentUser!.uid;
    final List<String> ids = [currentUserId, receiverId];
    ids.sort();
    final chatRoomId = ids.join('_');

    final starRef = _firestore
        .collection('Users')
        .doc(currentUserId)
        .collection('Starred_Messages')
        .doc(messageId);

    final doc = await starRef.get();

    if (doc.exists) {
      // if starred, unstar
      await starRef.delete();
    } else {
      // copy the data

      // create a clean copy of the map
      final data = Map<String, dynamic>.from(messageData);

      // add metadata

      data['starredAt'] = Timestamp.now();
      data['originalChatRoomId'] = chatRoomId;
      data['originalMessageId'] = messageId;

      // save
      await starRef.set(data);
    }
  }

  // Get starred messages stream
  Stream<QuerySnapshot> getStarredMessages() {
    final currentUserId = _auth.currentUser!.uid;
    return _firestore
        .collection('Users')
        .doc(currentUserId)
        .collection('Starred_Messages')
        .orderBy('starredAt', descending: true)
        .snapshots();
  }

  // ======================== TYPING INDICATOR ========================

  /// Update typing status for current user in a chat
  Future<void> setTypingStatus(String receiverId, bool isTyping) async {
    final currentUserId = _auth.currentUser!.uid;

    // Construct chat room ID
    List<String> ids = [currentUserId, receiverId];
    ids.sort();
    String chatRoomId = ids.join('_');

    await _firestore.collection('Chat_rooms').doc(chatRoomId).set({
      'typing': {currentUserId: isTyping ? Timestamp.now() : null},
    }, SetOptions(merge: true));
  }

  // Stream to listen for typing status of other user
  Stream<bool> getTypingStatus(String receiverId) {
    final currentUserId = _auth.currentUser!.uid;

    // Construct chat room ID
    List<String> ids = [currentUserId, receiverId];
    ids.sort();
    String chatRoomId = ids.join('_');

    return _firestore.collection('Chat_rooms').doc(chatRoomId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) return false;

      final data = snapshot.data();
      if (data == null || !data.containsKey('typing')) return false;

      final typing = data['typing'] as Map<String, dynamic>?;
      if (typing == null) return false;

      final otherUserTyping = typing[receiverId];
      if (otherUserTyping == null) return false;

      // Check if typing timestamp is recent (within last 5 seconds)
      if (otherUserTyping is Timestamp) {
        final typingTime = otherUserTyping.toDate();
        final now = DateTime.now();
        return now.difference(typingTime).inSeconds < 5;
      }

      return false;
    });
  }

  // Set user recording(audio) Status
  Future<void> setRecordingStatus(String receiverId, bool isRecording) async {
    final currentUserId = _auth.currentUser!.uid;

    // construct chatroom id
    List<String> ids = [currentUserId, receiverId];
    ids.sort();
    String chatRoomId = ids.join('_');

    _firestore.collection('Chat_rooms').doc(chatRoomId).set({
      'recording': {currentUserId: isRecording ? Timestamp.now() : null},
    }, SetOptions(merge: true));
  }

  Stream<bool> getRecordingStatus(String receiverId) {
    final currentUserId = _auth.currentUser!.uid;

    // construct chat room id
    List<String> ids = [currentUserId, receiverId];
    ids.sort();
    final String chatRoomId = ids.join('_');

    return _firestore.collection('Chat_rooms').doc(chatRoomId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) return false;

      final data = snapshot.data();
      if (data == null || !data.containsKey('recording')) return false;

      final recording = data['recording'] as Map<String, dynamic>?;
      if (recording == null) return false;

      final otherUserRecording = recording[receiverId];
      if (otherUserRecording == null) return false;

      // check if recording time is recent(within 5 seconds)
      if (otherUserRecording is Timestamp) {
        final recordingTime = otherUserRecording.toDate();
        final now = DateTime.now();
        return now.difference(recordingTime).inSeconds < 5;
      }
      return false;
    });
  }

  // Update current user's online status
  Future<void> setOnlineStatus(bool isOnline) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('Users').doc(user.uid).update({
      'isOnline': isOnline,
      'lastSeen': Timestamp.now(),
    });
  }

  // Stream to listen for a user's online status
  Stream<Map<String, dynamic>> getUserOnlineStatus(String userId) {
    return _firestore.collection('Users').doc(userId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) {
        return {'isOnline': false, 'lastSeen': null};
      }

      final data = snapshot.data();
      return {
        'isOnline': data?['isOnline'] ?? false,
        'lastSeen': data?['lastSeen'],
      };
    });
  }

  // create Group chat
  Future<String> createGroup(
    String groupName,
    List<String> selectedUserIds, {
    String? groupPhotoUrl,
    String? groupDescription,
  }) async {
    final currentUserId = _auth.currentUser!.uid;

    // list of members
    List<String> members = [currentUserId, ...selectedUserIds];

    // get chatroom doc(firestore Id)
    final newDocRef = _firestore.collection('Chat_rooms').doc();

    await newDocRef.set({
      'chatRoomId': newDocRef.id,
      'type': 'group',
      'groupName': groupName,
      'groupPhotoUrl': groupPhotoUrl,
      'groupDescription': groupDescription ?? '',
      'participants': members,
      'adminId': currentUserId,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': null,
      'lastMessageTimestamp': FieldValue.serverTimestamp(),
      'lastMessageStatus': null,
      'lastSenderId': null,
    });

    return newDocRef.id;
  }
}
