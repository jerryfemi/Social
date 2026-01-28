import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

part 'message_hive.g.dart';

class MessageStatus {
  static const String pending = 'pending';
  static const String sent = 'sent';
  static const String delivered = 'delivered';
  static const String read = 'read';
}

@HiveType(typeId: 0)
class Message extends HiveObject {
  @HiveField(0)
  final String senderID;

  @HiveField(1)
  final String senderEmail;

  @HiveField(2)
  final String senderName;

  @HiveField(3)
  final String receiverID;

  @HiveField(4)
  final String message;

  @HiveField(5)
  final DateTime timestamp;

  @HiveField(6)
  final String type;

  @HiveField(7)
  final String? caption;

  @HiveField(8)
  final String? status;

  @HiveField(9)
  final String? replyToId;

  @HiveField(10)
  final String? replyToMessage;

  @HiveField(11)
  final String? replyToSender;

  @HiveField(12)
  final String? replyToType;

  @HiveField(13)
  final int? voiceDuration;

  @HiveField(14)
  final String? thumbnailUrl;

  // unique local id(before firestore assigns one)
  @HiveField(15)
  final String localId;

  // firestore document id(null until synced)
  @HiveField(16)
  String? fireStoreId;

  @HiveField(17)
  MessageSyncStatus syncStatus;

  // local file path (for media before upload)
  @HiveField(18)
  final String? localFilePath;

  @HiveField(19)
  final bool? isEdited;

  @HiveField(20)
  final DateTime? editedAt;

  @HiveField(21)
  final List<String> deletedFor;

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
    this.replyToId,
    this.replyToMessage,
    this.replyToSender,
    this.replyToType,
    this.voiceDuration,
    this.thumbnailUrl,

    required this.localId,
    this.fireStoreId,
    this.syncStatus = MessageSyncStatus.pending,
    this.localFilePath,
    this.isEdited = false,
    this.editedAt,
    this.deletedFor = const [],
  });

  // convert to firestore format
  Map<String, dynamic> toFirestoreMap() {
    return {
      'senderID': senderID,
      'senderEmail': senderEmail,
      'receiverId': receiverID,
      'senderName': senderName,
      'message': message,
      'timestamp': Timestamp.fromDate(timestamp),
      'type': type,
      'localId': localId,
      if (caption != null) 'caption': caption,
      'status': status,
      if (replyToId != null) 'replyToId': replyToId,
      if (replyToMessage != null) 'replyToMessage': replyToMessage,
      if (replyToSender != null) 'replyToSender': replyToSender,
      if (replyToType != null) 'replyToType': replyToType,
      if (voiceDuration != null) 'voiceDuration': voiceDuration,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      if (isEdited != null) 'isEdited': isEdited,
      if (editedAt != null) 'editedAt': editedAt,
      if (deletedFor.isNotEmpty) 'deletedFor': deletedFor,
    };
  }

  // create from firestore document
  factory Message.fromFirestore(Map<String, dynamic> data, {String? docId}) {
    return Message(
      senderID: data['senderID'] ?? '',
      senderEmail: data['senderEmail'] ?? '',
      senderName: data['senderName'] ?? '',
      receiverID: data['receiverId'] ?? '',
      message: data['message'] ?? '',
      timestamp: (data['timestamp'] as Timestamp)
          .toDate(), // Convert to DateTime
      type: data['type'] ?? 'text',
      caption: data['caption'],
      status: data['status'] ?? MessageStatus.sent,
      replyToId: data['replyToId'],
      replyToMessage: data['replyToMessage'],
      replyToSender: data['replyToSender'],
      replyToType: data['replyToType'],
      voiceDuration: data['voiceDuration'],
      thumbnailUrl: data['thumbnailUrl'],
      localId: docId ?? data['localId'] ?? '',
      fireStoreId: docId,
      syncStatus: MessageSyncStatus.synced, // From Firestore = already synced
      isEdited: data['isEdited'] ?? false,
      editedAt: data['editedAt'] != null
          ? (data['editedAt'] as Timestamp).toDate()
          : null,
      deletedFor: data['deletedFor'] != null
          ? List<String>.from(data['deletedFor'])
          : [],
    );
  }

  // Create from notification data
  factory Message.fromNotification(Map<String, dynamic> data) {
    return Message(
      senderID: data['senderID'] ?? '',
      senderEmail: data['senderEmail'] ?? '',
      senderName: data['senderName'] ?? '',
      receiverID: data['receiverID'] ?? '',
      message: data['message'] ?? '',
      timestamp: DateTime.now(),
      type: data['type'] ?? 'text',
      status: data['status'] ?? 'delivered',
      localId: data['localId'] ?? data['messageId'] ?? const Uuid().v4(),
      fireStoreId: data['messageId'],
      syncStatus: MessageSyncStatus.synced,
    );
  }

  // Copy with method (for updates)
  Message copyWith({
    String? senderID,
    String? senderEmail,
    String? senderName,
    String? receiverID,
    String? message,
    DateTime? timestamp,
    String? type,
    String? caption,
    String? status,
    String? replyToId,
    String? replyToMessage,
    String? replyToSender,
    String? replyToType,
    int? voiceDuration,
    String? thumbnailUrl,
    String? localId,
    String? firestoreId,
    MessageSyncStatus? syncStatus,
    String? localFilePath,
    bool? isEdited,
    DateTime? editedAt,
    List<String>? deletedFor,
  }) {
    return Message(
      senderID: senderID ?? this.senderID,
      senderEmail: senderEmail ?? this.senderEmail,
      senderName: senderName ?? this.senderName,
      receiverID: receiverID ?? this.receiverID,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      caption: caption ?? this.caption,
      status: status ?? this.status,
      replyToId: replyToId ?? this.replyToId,
      replyToMessage: replyToMessage ?? this.replyToMessage,
      replyToSender: replyToSender ?? this.replyToSender,
      replyToType: replyToType ?? this.replyToType,
      voiceDuration: voiceDuration ?? this.voiceDuration,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      localId: localId ?? this.localId,
      fireStoreId: firestoreId ?? fireStoreId,
      syncStatus: syncStatus ?? this.syncStatus,
      localFilePath: localFilePath ?? this.localFilePath,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
      deletedFor: deletedFor ?? this.deletedFor,
    );
  }
}

// sync status
@HiveType(typeId: 1)
enum MessageSyncStatus {
  @HiveField(0)
  pending,

  @HiveField(1)
  syncing,

  @HiveField(2)
  synced,

  @HiveField(3)
  failed,
}
