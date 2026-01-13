import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:social/models/message.dart';
import 'package:social/services/auth_service.dart';
import 'package:social/services/storage_service.dart';

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
            final userData = userDoc.data() as Map<String, dynamic>;

            // Combine User Data with Chat Room Data (for last message info)
            recentChats.add({
              ...userData, // username, profileImage, etc.
              'lastMessage': chatRoomData['lastMessage'] ?? '',
              'lastMessageTimestamp': chatRoomData['lastMessageTimestamp'],
              'lastMessageStatus': chatRoomData['lastMessageStatus'],
              'lastSenderId': chatRoomData['lastSenderId'],
            });
          }
          return recentChats;
        });
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
    message,
    String status, {
    String? replyToId,
    String? replyToMessage,
    String? replyToSender,
    String? replyToType,
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
      timestamp: timestamp,
      senderName: username,
      status: status,
      replyToId: replyToId,
      replyToMessage: replyToMessage,
      replyToSender: replyToSender,
      replyToType: replyToType,
    );
    // construct chat room ID for the two users
    List<String> ids = [currentUserID, receiverID];
    ids.sort();
    String chatRoomID = ids.join('_');

    // add new message to database
    await _firestore
        .collection('Chat_rooms')
        .doc(chatRoomID)
        .collection("Messages")
        .add(newMessage.toMap());

    await _firestore
        .collection('Chat_rooms')
        .doc(chatRoomID)
        .collection('Messages')
        .doc()
        .set({});

    await _firestore.collection('Chat_rooms').doc(chatRoomID).set({
      'participants': [currentUserID, receiverID],
      'lastMessage': message,
      'lastMessageTimestamp': timestamp,
      'lastMessageStatus': status,
      'lastSenderId': currentUserID,
    }, SetOptions(merge: true));
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
            print("Delivered ${snapshot.docs.length} messages globally.");
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

  // send image message
  Future<void> sendMediaMessage(
    String receiverID,
    String fileName, {
    Uint8List? imageBytes,
    String? caption,
    String? videoPath,
    String? replyToId,
    String? replyToMessage,
    String? replyToSender,
    String? replyToType,
  }) async {
    final String currentuserID = _auth.currentUser!.uid;
    final String currentuserEmail = _auth.currentUser!.email!;
    final Timestamp timestamp = Timestamp.now();

    // construct chat room id
    List<String> ids = [currentuserID, receiverID];
    ids.sort();
    String chatRoomID = ids.join('_');

    String mediaUrl;
    String type;
    String notificationText;

    if (videoPath != null) {
      // upload images to storage
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
      timestamp: timestamp,
      type: type,
      replyToId: replyToId,
      replyToMessage: replyToMessage,
      replyToSender: replyToSender,
      replyToType: replyToType,
    );

    // add to firestore
    await _firestore
        .collection('Chat_rooms')
        .doc(chatRoomID)
        .collection('Messages')
        .add(message.toMap());

    // update last message
    String lastMsg = caption != null
        ? '$notificationText: $caption'
        : notificationText;

    await _firestore.collection('Chat_rooms').doc(chatRoomID).set({
      'participants': [currentuserID, receiverID],
      'lastMessage': lastMsg,
      'lastMessageTimestamp': timestamp,
      'lastMessageStatus': MessageStatus.sent,
      'lastSenderId': currentuserID,
    }, SetOptions(merge: true));
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
}
