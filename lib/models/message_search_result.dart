import 'package:social/models/message_hive.dart';

/// Represents a search result when searching through messages
class MessageSearchResult {
  final String chatRoomId;
  final String otherUserId; // The user ID to navigate to
  final String chatName;
  final String? chatPhotoUrl;
  final bool isGroup;
  final Message message;
  final String query;

  MessageSearchResult({
    required this.chatRoomId,
    required this.otherUserId,
    required this.chatName,
    this.chatPhotoUrl,
    required this.isGroup,
    required this.message,
    required this.query,
  });

  /// Returns the uid to navigate to (for routing)
  String get navigateId => otherUserId;
}
