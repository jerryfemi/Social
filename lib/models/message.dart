// import 'package:cloud_firestore/cloud_firestore.dart';

// class MessageStatus {
//   static const String sent = 'sent';
//   static const String delivered = 'delivered';
//   static const String read = 'read';
// }

// class Message {
//   final String senderID;
//   final String senderEmail;
//   final String senderName;
//   final String receiverID;
//   final String message;
//   final Timestamp timestamp;
//   final String type;
//   final String? caption;
//   final String? status;
//   // Reply fields
//   final String? replyToId;
//   final String? replyToMessage;
//   final String? replyToSender;
//   final String? replyToType;
//   // Voice message fields
//   final int? voiceDuration;
//   // Video thumbnail
//   final String? thumbnailUrl;

//   Message({
//     required this.senderID,
//     required this.senderEmail,
//     required this.senderName,
//     required this.receiverID,
//     required this.message,
//     required this.timestamp,
//     this.type = 'text',
//     this.caption,
//     this.status = MessageStatus.sent,
//     this.replyToId,
//     this.replyToMessage,
//     this.replyToSender,
//     this.replyToType,
//     this.voiceDuration,
//     this.thumbnailUrl,
//   });

//   // conver to map

//   Map<String, dynamic> toMap() {
//     return {
//       'senderID': senderID,
//       'senderEmail': senderEmail,
//       'receiverId': receiverID,
//       'senderName': senderName,
//       'message': message,
//       'timestamp': timestamp,
//       'type': type,
//       'caption': caption,
//       'status': status,
//       if (replyToId != null) 'replyToId': replyToId,
//       if (replyToMessage != null) 'replyToMessage': replyToMessage,
//       if (replyToSender != null) 'replyToSender': replyToSender,
//       if (replyToType != null) 'replyToType': replyToType,
//       if (voiceDuration != null) 'voiceDuration': voiceDuration,
//       if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
//     };
//   }
// }
