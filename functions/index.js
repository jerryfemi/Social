const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();

exports.sendChatNotification = functions.firestore
  .document("Chat_rooms/{chatRoomId}/Messages/{messageId}")
  .onCreate(async (snapshot, context) => {

    const messageData = snapshot.data();
    const receiverId = messageData.receiverId;
    const senderId = messageData.senderID;
    const senderName = messageData.senderName;
    const messageContent = messageData.message;
    const type = messageData.type;
    const photoUrl = messageData.senderPhotoUrl || '';

    console.log(`New message from ${senderName} to ${receiverId}`);

    try {
      const userDoc = await admin.firestore()
        .collection("Users")
        .doc(receiverId)
        .get();

      if (!userDoc.exists) {
        console.log("No user found");
        return;
      }

      const userData = userDoc.data();
      const fcmToken = userData.token;

      if (!fcmToken) {
        console.log("User has no FCM Token registered");
        return;
      }

      let bodyText = messageContent;
      if (type === 'image') bodyText = '📷 Sent a photo';
      if (type === 'video') bodyText = '🎥 Sent a video';
      if (type === 'voice') bodyText = '🎤 Sent a voice message';

      const payload = {
        token: fcmToken,
        notification: {
          title: senderName,
          body: bodyText,
        },
        android: {
          notification: {
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
            sound: "default",
            // Group notifications by sender
            tag: senderId,
            // Notification grouping
            notificationCount: 1,
          },
          // Collapse key groups notifications
          collapseKey: senderId,
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
              // Thread identifier for iOS grouping
              threadId: senderId,
            },
          },
        },
        data: {
          chatRoomId: context.params.chatRoomId,
          senderID: senderId,
          senderName: senderName,
          photoUrl: photoUrl,
          type: "chat_message",
        },
      };

      await admin.messaging().send(payload);
      console.log("Notification sent successfully!");

    } catch (error) {
      console.error("Error sending notification:", error);
    }
  });