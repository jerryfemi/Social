import 'package:cloud_firestore/cloud_firestore.dart';

class MessageStatus {
  static const String sent = 'sent';
  static const String delivered = 'delivered';
  static const String read = 'read';
}

class Message {
  final String senderID;
  final String senderEmail;
  final String senderName;
  final String receiverID;
  final String message;
  final Timestamp timestamp;
  final String type;
  final String? caption;
  final String? status;

  Message({
    required this.senderID,
    required this.senderEmail,
    required this.senderName,
    required this.receiverID,
    required this.message,
    required this.timestamp,
    this.type = 'text',
    this.caption,
    this.status = MessageStatus.sent,
  });

  // conver to map

  Map<String, dynamic> toMap() {
    return {
      'senderID': senderID,
      'senderEmail': senderEmail,
      'receiverId': receiverID,
      'senderName': senderName,
      'message': message,
      'timestamp': timestamp,
      'type': type,
      'caption': caption,
      'status': status,
    };
  }
}
