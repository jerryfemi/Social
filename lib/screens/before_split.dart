// import 'dart:async';
// import 'dart:typed_data';

// import 'package:cached_network_image/cached_network_image.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';
// import 'package:image_cropper/image_cropper.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:mime/mime.dart';
// import 'package:skeletonizer/skeletonizer.dart';
// import 'package:social/providers/chat_message_provider.dart';
// import 'package:social/services/auth_service.dart';
// import 'package:social/services/notification_service.dart';
// import 'package:social/providers/chat_provider.dart';
// import 'package:social/utils/date_utils.dart';
// import 'package:social/widgets/chat_bubble.dart';
// import 'package:social/widgets/voice_recorder_button.dart';
// import 'package:video_thumbnail/video_thumbnail.dart';

// import '../models/message_hive.dart' as hive_model;

// class ChatScreen extends ConsumerStatefulWidget {
//   final String receiverName;
//   final String receiverId;
//   final String? photoUrl;
//   const ChatScreen({
//     super.key,
//     required this.receiverName,
//     required this.receiverId,
//     required this.photoUrl,
//   });

//   @override
//   ConsumerState<ChatScreen> createState() => _ChatScreenState();
// }

// class _ChatScreenState extends ConsumerState<ChatScreen> {
//   final _messageController = TextEditingController();
//   final authService = AuthService();
//   final _notificationService = NotificationService();
//   final FocusNode _focusNode = FocusNode();
//   final ScrollController _scrollController = ScrollController();
//   bool _showAttachments = false;
//   final ImagePicker imagePicker = ImagePicker();
//   Uint8List? _selectedImageBytes;
//   String? _selectedImageName;
//   String? _selectedMediaType;
//   String? _selectedVideoPath;

//   // Reply state
//   Map<String, dynamic>? _replyingTo;
//   String? _replyingToId;
//   String? _replyingToSender;

//   // Voice recording state
//   bool _isRecording = false;
//   final GlobalKey<VoiceRecorderButtonState> _voiceRecorderKey = GlobalKey();

//   // Track if text field has content
//   bool _hasText = false;

//   // Highlight state for scroll-to-message
//   String? _highlightedMessageId;
//   final Map<String, GlobalKey> _messageKeys = {};

 

//   // Typing indicator
//   Timer? _typingTimer;
//   bool _isTyping = false;

//   // Helper method to get chat room ID
//   String _getChatRoomId(String userId1, String userId2) {
//     final ids = [userId1, userId2]..sort();
//     return ids.join('_');
//   }

//   @override
//   void initState() {
//     super.initState();

//     // Tell notification service we're in this chat (suppress notifications from this user)
//     _notificationService.setCurrentChat(widget.receiverId);

//     // scroll down if focusNode has focus
//     _focusNode.addListener(() {
//       if (_focusNode.hasFocus) {
//         setState(() {
//           _showAttachments = false;
//         });
//         Future.delayed(Duration(milliseconds: 300), () => _scrollDown());
//       }
//       // Trigger rebuild when focus changes
//       setState(() {});
//     });

//     // Listen for text changes and update typing status
//     _messageController.addListener(_onTextChanged);
//   }

//   void _onTextChanged() {
//     final hasText = _messageController.text.trim().isNotEmpty;
//     if (hasText != _hasText) {
//       setState(() {
//         _hasText = hasText;
//       });
//     }

//     // Update typing status
//     if (_messageController.text.isNotEmpty) {
//       _setTyping(true);
//     }
//   }

//   void _setTyping(bool typing) {
//     if (typing) {
//       // Set typing to true
//       if (!_isTyping) {
//         _isTyping = true;
//         ref.read(chatServiceProvider).setTypingStatus(widget.receiverId, true);
//       }

//       // Reset the timer
//       _typingTimer?.cancel();
//       _typingTimer = Timer(const Duration(seconds: 3), () {
//         _isTyping = false;
//         ref.read(chatServiceProvider).setTypingStatus(widget.receiverId, false);
//       });
//     } else {
//       _typingTimer?.cancel();
//       _isTyping = false;
//       ref.read(chatServiceProvider).setTypingStatus(widget.receiverId, false);
//     }
//   }

//   // dispose
//   @override
//   void dispose() {
//     // Clear typing status
//     _typingTimer?.cancel();
//     if (_isTyping) {
//       ref.read(chatServiceProvider).setTypingStatus(widget.receiverId, false);
//     }
//     // Clear current chat so notifications show again
//     _notificationService.clearCurrentChat();
//     _focusNode.dispose();
//     _scrollController.dispose();
//     _messageController.removeListener(_onTextChanged);
//     _messageController.dispose();
//     super.dispose();
//   }

//   void _toggleAttachments() {
//     setState(() {
//       _showAttachments = !_showAttachments;
//       if (_showAttachments) {
//         // close keyboard
//         _focusNode.unfocus();
//       }
//     });

//     // Scroll to bottom after menu opens
//     if (_showAttachments) {
//       Future.delayed(const Duration(milliseconds: 300), () => _scrollDown());
//     }
//   }

//   // scroll down
//   void _scrollDown({bool immediate = false}) {
//     if (_scrollController.hasClients) {
//       if (immediate) {
//         _scrollController.jumpTo(0.0);
//       } else {
//         _scrollController.animateTo(
//           0.0,
//           duration: const Duration(milliseconds: 300),
//           curve: Curves.easeOut,
//         );
//       }
//     }
//   }

//   // Scroll to a specific message and highlight it
//   void _scrollToMessage(String messageId) {
//     final key = _messageKeys[messageId];
//     if (key?.currentContext != null) {
//       // Scroll to the message
//       Scrollable.ensureVisible(
//         key!.currentContext!,
//         duration: const Duration(milliseconds: 300),
//         curve: Curves.easeOut,
//         alignment: 0.5, // Center the message
//       );

//       // Highlight the message briefly
//       setState(() {
//         _highlightedMessageId = messageId;
//       });

//       // Remove highlight after animation
//       Future.delayed(const Duration(milliseconds: 1000), () {
//         if (mounted) {
//           setState(() {
//             _highlightedMessageId = null;
//           });
//         }
//       });
//     }
//   }

//   // send message
//   void sendMessage() async {
//     final text = _messageController.text.trim();

//     if (text.isEmpty && _selectedImageBytes == null) return;

//     final imageBytes = _selectedImageBytes;
//     final videoPath = _selectedVideoPath;
//     final mediaName = _selectedImageName;
//     final isVideo = _selectedMediaType == 'video';

//     // Capture reply data before clearing
//     final replyToId = _replyingToId;
//     final replyToMessage = _replyingTo?['message'] as String?;
//     final replyToSender = _replyingToSender;
//     final replyToType = _replyingTo?['type'] as String? ?? 'text';

//     // get chat room Id
//     final currentUserId = authService.currentUser!.uid;
//     final chatRoomId = _getChatRoomId(currentUserId, widget.receiverId);
//     final notifier = ref.read(chatMessagesProvider(chatRoomId).notifier);

//     try {
//       if (imageBytes != null) {
//         // SEND MEDIA
//         await notifier.sendMediaMessage(
//         receiverId: widget.receiverId,
//         receiverName: widget.receiverName,
//         fileName: mediaName ?? (isVideo ? 'video.mp4' : 'image.jpg'),
//         imageBytes: isVideo ? null : imageBytes,
//         videoPath: isVideo ? videoPath : null,
//         caption: text.isNotEmpty ? text : null,
//         replyToId: replyToId,
//         replyToMessage: replyToMessage,
//         replyToSender: replyToSender,
//         replyToType: replyToType,
//       );

//         _clearImage();
//       } else {
//         // send message
//         await notifier.sendTextMessage(
//         receiverId: widget.receiverId,
//         receiverName: widget.receiverName,
//         text: text,
//         replyToId: replyToId,
//         replyToMessage: replyToMessage,
//         replyToSender: replyToSender,
//         replyToType: replyToType,
//       );

//       }

//       // clear textfield and reply
//       _messageController.clear();
//       _clearReply();
//       _setTyping(false); // Clear typing status when message sent

//       // scroll down after sending mesage
//       _scrollDown();
//     } catch (e) {
//       _showSnackBar('Error: $e');
//     }
//   }

//   // Send voice message
//   void _sendVoiceMessage(String voicePath, int duration) async {
//     // Capture reply data before clearing
//     final replyToId = _replyingToId;
//     final replyToMessage = _replyingTo?['message'] as String?;
//     final replyToSender = _replyingToSender;
//     final replyToType = _replyingTo?['type'] as String? ?? 'text';

//     // get chat room id
//     final currentUserId = authService.currentUser!.uid;
//   final chatRoomId = _getChatRoomId(currentUserId, widget.receiverId);
//   final notifier = ref.read(chatMessagesProvider(chatRoomId).notifier);


//     try {
//          await notifier.sendVoiceMessage(
//       receiverId: widget.receiverId,
//       receiverName: widget.receiverName,
//       localPath: voicePath,
//       duration: duration,
//       replyToId: replyToId,
//       replyToMessage: replyToMessage,
//       replyToSender: replyToSender,
//       replyToType: replyToType,
//     );


//       // Clear reply
//       _clearReply();

//       // Scroll down after sending
//       _scrollDown();
//     } catch (e) {
//       _showSnackBar('Error sending voice message: $e');
//     }
//   }

//   // Set reply to message
//   void _setReplyTo(
//     Map<String, dynamic> data,
//     String messageId,
//     String senderName,
//   ) {
//     setState(() {
//       _replyingTo = data;
//       _replyingToId = messageId;
//       _replyingToSender = senderName;
//     });
//     _focusNode.requestFocus();
//   }

//   // Clear reply
//   void _clearReply() {
//     setState(() {
//       _replyingTo = null;
//       _replyingToId = null;
//       _replyingToSender = null;
//     });
//   }

//   // show snackbar
//   void _showSnackBar(String title) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(title, style: TextStyle()),
//         duration: Duration(seconds: 2),
//       ),
//     );
//   }

//   // pick and send image
//   Future<void> _pickImage() async {
//     try {
//       final XFile? pickedFile = await imagePicker.pickMedia(
//         imageQuality: 70,
//         requestFullMetadata: false,
//       );

//       if (pickedFile == null) {
//         print('No file selected');
//         return;
//       }

//       // On web, use mimeType property; on mobile, use lookupMimeType
//       String? mime = pickedFile.mimeType;
//       if (mime == null || mime.isEmpty) {
//         mime = lookupMimeType(pickedFile.path);
//       }

//       print('Picked file: ${pickedFile.name}, mime: $mime');

//       final isImage = mime?.startsWith('image') == true;
//       final isVideo = mime?.startsWith('video') == true;

//       if (isImage) {
//         print('Image picked');

//         // On mobile, use image cropper
//         await cropImage(pickedFile);

//         print('IMAGE READY ≡ƒƒó');
//       } else if (isVideo) {
//         print('Video picked');

//         // On mobile, use video trimmer
//         if (!mounted) return;
//         final String? trimmedPath = await context.push(
//           '/editVideo',
//           extra: pickedFile.path,
//         );

//         if (trimmedPath != null) {
//           final Uint8List? thumbBytes = await VideoThumbnail.thumbnailData(
//             video: trimmedPath,
//             imageFormat: ImageFormat.JPEG,
//             quality: 75,
//           );

//           setState(() {
//             _selectedImageBytes = thumbBytes;
//             _selectedVideoPath = trimmedPath;
//             _selectedMediaType = 'video';
//             _showAttachments = false;
//           });
//         }
//       } else {
//         print('Unknown media type: $mime');
//         _showSnackBar('Unsupported file type');
//       }
//     } catch (e) {
//       print('Error picking image: $e');
//       _showSnackBar('Error: $e');
//     }
//   }

//   // CROP IMAGE
//   Future<void> cropImage(XFile imageFile) async {
//     try {
//       final CroppedFile? croppedFile = await ImageCropper().cropImage(
//         sourcePath: imageFile.path,
//         uiSettings: [
//           AndroidUiSettings(
//             toolbarColor: Theme.of(context).colorScheme.secondary,
//             toolbarWidgetColor: Theme.of(context).colorScheme.primary,
//             initAspectRatio: CropAspectRatioPreset.original,
//             lockAspectRatio: false,
//           ),
//           WebUiSettings(context: context),
//         ],
//       );

//       if (croppedFile != null) {
//         final bytes = await croppedFile.readAsBytes();

//         setState(() {
//           _selectedImageBytes = bytes;
//           _selectedImageName = imageFile.name;
//         });
//         _focusNode.requestFocus();
//       }
//       print('IMAGE CROP SUCCESSFUL ≡ƒƒó ');
//     } catch (e) {
//       print('FAILED TO CROP IMAGE≡ƒö┤: $e');
//     }
//   }

//   void _clearImage() {
//     setState(() {
//       _selectedImageBytes = null;
//       _selectedImageName = null;
//       _selectedVideoPath = null;
//       _selectedMediaType = null;
//     });
//   }

//   // SET WALLPAPER
//   Future<void> _setWallpaper() async {
//     try {
//       final XFile? pickedFile = await imagePicker.pickImage(
//         source: ImageSource.gallery,
//       );

//       // set wallpaper
//       if (pickedFile != null) {
//         setState(() => _showAttachments = false);

//         Uint8List filebytes = await pickedFile.readAsBytes();
//         String fileName = pickedFile.name;

//         // set wallpaper
//         await ref
//             .read(chatServiceProvider)
//             .setChatWallpaper(widget.receiverId, filebytes, fileName);

//         _showSnackBar('Wallpaper set!');
//       }
//     } catch (e) {
//       _showSnackBar('Failed to set wallpaper: $e');
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     // ============ NEW: Listen to Hive-first provider ============
//     final currentUserId = authService.currentUser!.uid;
//     final chatRoomId = _getChatRoomId(currentUserId, widget.receiverId);

//     ref.listen<AsyncValue<List<hive_model.Message>>>(
//       chatMessagesProvider(chatRoomId),
//       (previous, next) {
//         next.whenData((messages) {
//           if (!mounted) return;

//           // Mark messages as read
//           Future.delayed(Duration.zero, () {
//             ref
//                 .read(chatServiceProvider)
//                 .messageRead(currentUserId, widget.receiverId);
//           });

//           // Auto-scroll when new messages arrive
//           Future.delayed(const Duration(milliseconds: 100), () {
//             if (_scrollController.hasClients) {
//               _scrollDown();
//             }
//           });
//         });
//       },
//     );
//     // ============================================================

//     final chatRoomAsync = ref.watch(chatStreamProvider(widget.receiverId));
//     final dateUtil = DateUtil();

//     return Scaffold(
//       appBar: AppBar(
//         title: InkWell(
//           onTap: () => context.push(
//             '/chat_profile/${widget.receiverId}',
//             extra: widget.photoUrl,
//           ),
//           child: Row(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               ClipOval(
//                 child: widget.photoUrl != null && widget.photoUrl!.isNotEmpty
//                     ? CachedNetworkImage(
//                         imageUrl: widget.photoUrl!,
//                         height: 44,
//                         width: 44,
//                         fit: BoxFit.cover,
//                         placeholder: (context, url) =>
//                             const CircularProgressIndicator(),
//                         errorWidget: (context, url, error) => Icon(
//                           Icons.person,
//                           size: 20,
//                           color: Theme.of(context).colorScheme.tertiary,
//                         ),
//                       )
//                     : CircleAvatar(
//                         backgroundColor: Theme.of(context).colorScheme.surface,
//                         radius: 22,
//                         child: Icon(
//                           Icons.person,
//                           size: 20,
//                           color: Theme.of(context).colorScheme.tertiary,
//                         ),
//                       ),
//               ),
//               SizedBox(width: 10),
//               Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   Text(
//                     widget.receiverName,
//                     style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
//                   ),
//                   // Typing indicator or Online status
//                   Consumer(
//                     builder: (context, ref, child) {
//                       final typingAsync = ref.watch(
//                         typingStatusProvider(widget.receiverId),
//                       );
//                       final onlineAsync = ref.watch(
//                         onlineStatusProvider(widget.receiverId),
//                       );
//                       final isTyping = typingAsync.value ?? false;
//                       final onlineData = onlineAsync.value;
//                       final isOnline = onlineData?['isOnline'] ?? false;

//                       // Priority: typing > online > last seen
//                       if (isTyping) {
//                         return Text(
//                           'typing...',
//                           style: TextStyle(
//                             fontSize: 12,
//                             color: Theme.of(context).colorScheme.primary,
//                             fontStyle: FontStyle.italic,
//                           ),
//                         );
//                       }

//                       if (isOnline) {
//                         return Row(
//                           mainAxisSize: MainAxisSize.min,
//                           children: [
//                             Container(
//                               width: 8,
//                               height: 8,
//                               decoration: BoxDecoration(
//                                 color: Colors.green,
//                                 shape: BoxShape.circle,
//                               ),
//                             ),
//                             const SizedBox(width: 4),
//                             Text(
//                               'Active now',
//                               style: TextStyle(
//                                 fontSize: 12,
//                                 color: Colors.green,
//                               ),
//                             ),
//                           ],
//                         );
//                       }

//                       // Show last seen if not online
//                       final lastSeen = onlineData?['lastSeen'];
//                       if (lastSeen != null) {
//                         return Text(
//                           dateUtil.formatLastSeen(lastSeen),
//                           style: TextStyle(
//                             fontSize: 12,
//                             color: Theme.of(
//                               context,
//                             ).colorScheme.onSurface.withValues(alpha: 0.6),
//                           ),
//                         );
//                       }

//                       return const SizedBox.shrink();
//                     },
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       ),
//       body: chatRoomAsync.when(
//         error: (error, stackTrace) =>
//             Center(child: Text('Error fetching chats $error')),
//         loading: () => const Center(child: CircularProgressIndicator()),
//         data: (snapShot) {
//           final chatData = snapShot.data() as Map<String, dynamic>?;
//           String? wallpaperUrl;

//           print('CHAT DATA : $chatData');
//           //  CHECK IF DATA AND WALLPAPERS EXIST
//           if (chatData != null && chatData.containsKey('wallpaper')) {
//             final wallpapers = chatData['wallpaper'] as Map<String, dynamic>?;
//             wallpaperUrl = wallpapers?[authService.currentUser!.uid];

//             print('FOUND WALLPAPER URL : $wallpaperUrl');
//           }
//           return Container(
//             decoration: BoxDecoration(
//               image: wallpaperUrl != null
//                   ? DecorationImage( 
//                       image: CachedNetworkImageProvider(wallpaperUrl),
//                       fit: BoxFit.cover,
//                     )
//                   : null,
//             ),
//             child: Column(
//               children: [
//                 // display messages
//                 Expanded(child: _buildMessageList()),
//                 _buildMessageInput(context),
//               ],
//             ),
//           );
//         },
//       ),
//     );
//   }

//   // build message list
//   Widget _buildMessageList() {
//     final currentUserId = authService.currentUser!.uid;
//     final chatRoomId = _getChatRoomId(currentUserId, widget.receiverId);

//     final messagesAsync = ref.watch(chatMessagesProvider(chatRoomId));

//     return Padding(
//       padding: const EdgeInsets.only(left: 15, right: 15, top: 5),
//       child: messagesAsync.when(
//         // Loading state (only shows on first load when Hive is empty)
//         loading: () => _buildSkeletonMessages(),

//         // Error state
//         error: (error, stack) => Center(
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               const Icon(Icons.error_outline, size: 48, color: Colors.red),
//               const SizedBox(height: 16),
//               Text('Error loading messages'),
//               const SizedBox(height: 8),
//               Text(error.toString(), style: TextStyle(fontSize: 12)),
//             ],
//           ),
//         ),

//         // Data state - messages loaded from Hive
//         data: (messages) {
//           if (messages.isEmpty) {
//             return const Center(child: Text('No Messages yet'));
//           }

//           // Messages are already sorted (oldest first) from HiveService
//           // Reverse for UI display (newest at bottom)
//           final reversedMessages = messages.reversed.toList();

//           return ListView.builder(
//             reverse: true,
//             controller: _scrollController,
//             itemCount: reversedMessages.length,
//             itemBuilder: (context, index) {
//               return _buildHiveMessageItemWithDate(
//                 reversedMessages,
//                 index,
//                 context,
//               );
//             },
//           );
//         },
//       ),
//     );
//   }

//   Widget _buildHiveMessageItemWithDate(
//     List<hive_model.Message> messages,
//     int index,
//     BuildContext context,
//   ) {
//     final message = messages[index];
//     final messageDate = message.timestamp;

//     bool showHeader = false;

//     // If it's the last message (oldest), show header
//     if (index == messages.length - 1) {
//       showHeader = true;
//     } else {
//       // Check if date is different from next message
//       final nextMessage = messages[index + 1];
//       final nextDate = nextMessage.timestamp;

//       if (!DateUtil.isSameDay(messageDate, nextDate)) {
//         showHeader = true;
//       }
//     }

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.stretch,
//       children: [
//         if (showHeader) _buildDateHeader(messageDate),
//         _buildHiveMessageItem(message, context),
//       ],
//     );
//   }

//   // BUILD SKELETON MESSAGES FOR LOADING STATE
//   Widget _buildSkeletonMessages() {
//     return Skeletonizer(
//       enabled: true,
//       child: ListView.builder(
//         itemCount: 10,
//         itemBuilder: (context, index) {
//           final isSender = index % 2 == 0;
//           return ChatBubble(
//             alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
//             isSender: isSender,
//             data: {
//               'message': BoneMock.paragraph,
//               'timestamp': Timestamp.now(),
//               'type': 'text',
//               'status': 'read',
//             },
//             bubbleColor: isSender ? Colors.purpleAccent : Colors.grey,
//             messageId: '',
//             userId: '',
//             senderName: '',
//             receiverId: '',
//           );
//         },
//       ),
//     );
//   }

//   // build date header
//   Widget _buildDateHeader(DateTime date) {
//     return Center(
//       child: Container(
//         padding: const EdgeInsetsGeometry.symmetric(
//           vertical: 6,
//           horizontal: 12,
//         ),
//         margin: EdgeInsets.symmetric(vertical: 15),
//         decoration: BoxDecoration(
//           color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.2),
//           borderRadius: BorderRadius.circular(12),
//         ),
//         child: Text(DateUtil.getDateLabel(date)),
//       ),
//     );
//   }

//   // build message item list
//   Widget _buildHiveMessageItem(
//     hive_model.Message message,
//     BuildContext context,
//   ) {
//     final currentUserId = authService.currentUser!.uid;
//     final isSender = message.senderID == currentUserId;
//     final alignment = isSender ? Alignment.centerRight : Alignment.centerLeft;
//     final bubbleColor = isSender ? Colors.purpleAccent : Colors.grey;
//     final name = isSender ? 'You' : widget.receiverName;

//     // Get starred status (still using old provider for now)
//     final starredAsync = ref.watch(starredMessagesProvider);
//     final starredIds = starredAsync.value?.docs.map((e) => e.id).toSet() ?? {};
//     final isStarred =
//         message.fireStoreId != null && starredIds.contains(message.fireStoreId);

//     // Store key for scroll-to-message
//     final messageKey = message.localId;
//     _messageKeys.putIfAbsent(messageKey, () => GlobalKey());

//     // Convert Hive message to Map for ChatBubble (temporary compatibility)
//     final messageData = _convertHiveMessageToMap(message);

//     return ChatBubble(
//       key: _messageKeys[messageKey],
//       senderName: name,
//       messageId: message.localId,
//       userId: message.senderID,
//       alignment: alignment,
//       isSender: isSender,
//       data: messageData,
//       bubbleColor: bubbleColor,
//       receiverId: widget.receiverId,
//       isStarred: isStarred,
//       isHighlighted: _highlightedMessageId == messageKey,
//       onReply: () => _setReplyTo(messageData, messageKey, name),
//       onReplyTap: _scrollToMessage,
//     );
//   }

//   // ============ Helper: Convert Hive Message to Map ============
//   Map<String, dynamic> _convertHiveMessageToMap(hive_model.Message msg) {
//     return {
//       'senderID': msg.senderID,
//       'senderEmail': msg.senderEmail,
//       'senderName': msg.senderName,
//       'receiverId': msg.receiverID,
//       'message': msg.message,
//       'timestamp': Timestamp.fromDate(
//         msg.timestamp,
//       ), 
//       'type': msg.type,
//       'caption': msg.caption,
//       'status': msg.status,
//       'replyToId': msg.replyToId,
//       'replyToMessage': msg.replyToMessage,
//       'replyToSender': msg.replyToSender,
//       'replyToType': msg.replyToType,
//       'voiceDuration': msg.voiceDuration,
//       'thumbnailUrl': msg.thumbnailUrl,
//       'isEdited': msg.isEdited,
//       'editedAt': msg.editedAt != null
//           ? Timestamp.fromDate(msg.editedAt!)
//           : null,
//       'deletedFor': msg.deletedFor,
//       'localFilePath': msg.localFilePath, 
//       'syncStatus': msg.syncStatus.toString(), 
//     };
//   }

//   // build message input
//   Widget _buildMessageInput(BuildContext context) {
//     return Column(
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         Container(
//           padding: const EdgeInsets.only(bottom: 20, left: 15, right: 15),
//           child: _buildNormalInput(context),
//         ),

//         // 2. THE ATTACHMENT DRAWER (hidden when recording)
//         if (!_isRecording)
//           AnimatedContainer(
//             duration: const Duration(milliseconds: 250),
//             curve: Curves.easeOut,
//             height: _showAttachments ? 120 : 0,
//             width: double.infinity,
//             clipBehavior: Clip.hardEdge,
//             decoration: BoxDecoration(),
//             child: SingleChildScrollView(
//               physics: const NeverScrollableScrollPhysics(),
//               child: Container(
//                 height: 120,
//                 padding: const EdgeInsets.only(top: 10),
//                 child: Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     // gallery buttpn
//                     GestureDetector(
//                       onTap: () => _pickImage(),
//                       child: _buildAttachmentOption(Icons.image, "Gallery"),
//                     ),

//                     // camera button
//                     GestureDetector(
//                       onTap: () => _pickImage(),
//                       child: _buildAttachmentOption(Icons.camera_alt, "Camera"),
//                     ),

//                     // wallpaper button
//                     GestureDetector(
//                       onTap: () => _setWallpaper(),
//                       child: _buildAttachmentOption(
//                         Icons.wallpaper_rounded,
//                         "Wallpaper",
//                       ),
//                     ),
//                     _buildAttachmentOption(Icons.person_pin_rounded, "Contact"),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//       ],
//     );
//   }

//   // REPLY PREVIEW WIDGET (inside TextField)
//   Widget _buildReplyPreview() {
//     final type = _replyingTo!['type'];
//     final isMedia = type == 'image' || type == 'video';
//     final isVoice = type == 'voice';

//     String messageText;
//     if (isVoice) {
//       messageText = '≡ƒÄñ Voice message';
//     } else if (isMedia) {
//       messageText = _replyingTo!['caption'] ?? '≡ƒô╖ Photo';
//     } else {
//       messageText = _replyingTo!['message'];
//     }

//     return Container(
//       margin: const EdgeInsets.only(left: 8, right: 8, top: 8),
//       padding: const EdgeInsets.all(8),
//       decoration: BoxDecoration(
//         color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5),
//         borderRadius: BorderRadius.circular(12),
//         border: Border(
//           left: BorderSide(
//             color: Theme.of(context).colorScheme.primary,
//             width: 2,
//           ),
//         ),
//       ),
//       child: Row(
//         children: [
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Text(
//                   _replyingToSender ?? '',
//                   style: TextStyle(
//                     fontWeight: FontWeight.bold,
//                     color: Theme.of(context).colorScheme.primary,
//                     fontSize: 12,
//                   ),
//                 ),
//                 const SizedBox(height: 2),
//                 Text(
//                   messageText,
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                   style: TextStyle(
//                     fontSize: 12,
//                     color: Theme.of(
//                       context,
//                     ).colorScheme.onSurface.withValues(alpha: 0.7),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           // Close button
//           GestureDetector(
//             onTap: _clearReply,
//             child: Icon(
//               Icons.close,
//               size: 18,
//               color: Theme.of(
//                 context,
//               ).colorScheme.onSurface.withValues(alpha: 0.5),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   // Normal input (text field + plus button)
//   Widget _buildNormalInput(BuildContext context) {
//     // When recording, show only the VoiceRecorderButton (expanded)
//     if (_isRecording) {
//       return VoiceRecorderButton(
//         key: _voiceRecorderKey,
//         onRecordingComplete: (path, duration) {
//           setState(() => _isRecording = false);
//           _sendVoiceMessage(path, duration);
//         },
//         onRecordingStart: () {},
//         onRecordingCancel: () => setState(() => _isRecording = false),
//       );
//     }

//     return Row(
//       crossAxisAlignment: CrossAxisAlignment.end,
//       children: [
//         _selectedImageBytes != null
//             // selected image preview
//             ? _buildImageThumbnail()
//             :
//               // PLUS BUTTON
//               InkWell(
//                 borderRadius: BorderRadius.circular(25),
//                 onTap: _toggleAttachments,
//                 child: Container(
//                   padding: EdgeInsets.all(8),
//                   decoration: BoxDecoration(
//                     color: Theme.of(context).colorScheme.secondary,
//                     shape: BoxShape.circle,
//                   ),
//                   child: AnimatedRotation(
//                     turns: _showAttachments ? 0.125 : 0,
//                     duration: const Duration(milliseconds: 200),
//                     child: Icon(
//                       Icons.add,
//                       size: 26,
//                       color: Theme.of(context).colorScheme.primary,
//                     ),
//                   ),
//                 ),
//               ),

//         const SizedBox(width: 10),
//         Expanded(
//           child: Container(
//             decoration: BoxDecoration(
//               color:
//                   Theme.of(context).inputDecorationTheme.fillColor ??
//                   Theme.of(context).colorScheme.surfaceContainerHighest,
//               borderRadius: BorderRadius.circular(20),
//               border: Border.all(
//                 color: Theme.of(context).colorScheme.secondary,
//                 width: 2,
//               ),
//             ),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 // Reply preview
//                 if (_replyingTo != null) _buildReplyPreview(),
//                 // Text field
//                 TextField(
//                   focusNode: _focusNode,
//                   controller: _messageController,
//                   autocorrect: true,
//                   textCapitalization: TextCapitalization.sentences,
//                   keyboardType: TextInputType.multiline,
//                   maxLines: 5,
//                   minLines: 1,
//                   textInputAction: TextInputAction.newline,
//                   decoration: InputDecoration(
//                     filled: true,
//                     fillColor: Colors.transparent,
//                     hintText: _selectedImageBytes != null
//                         ? 'Add a caption...'
//                         : null,
//                     isDense: true,
//                     contentPadding: const EdgeInsets.symmetric(
//                       horizontal: 16,
//                       vertical: 10,
//                     ),
//                     enabledBorder: InputBorder.none,
//                     focusedBorder: InputBorder.none,
//                     border: InputBorder.none,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),

//         // Voice recorder or send button
//         const SizedBox(width: 8),
//         if (_hasText || _selectedImageBytes != null)
//           _sendButton(context, sendMessage)
//         else
//           VoiceRecorderButton(
//             key: _voiceRecorderKey,
//             onRecordingComplete: _sendVoiceMessage,
//             onRecordingStart: () => setState(() => _isRecording = true),
//             onRecordingCancel: () => setState(() => _isRecording = false),
//           ),
//       ],
//     );
//   }

//   //  THUMBNAIL WIDGET
//   Widget _buildImageThumbnail() {
//     return Padding(
//       padding: const EdgeInsets.only(left: 10, right: 8),
//       child: Stack(
//         clipBehavior: Clip.none,
//         children: [
//           GestureDetector(
//             onTap: () => _pickImage(),
//             child: Container(
//               height: 40,
//               width: 40,
//               decoration: BoxDecoration(
//                 borderRadius: BorderRadius.circular(10),
//                 border: Border.all(color: Colors.white, width: 2),
//                 image: DecorationImage(
//                   image: MemoryImage(_selectedImageBytes!),
//                   fit: BoxFit.cover,
//                 ),
//               ),
//             ),
//           ),

//           // cancel button
//           Positioned(
//             top: -8,
//             right: -8,
//             child: GestureDetector(
//               onTap: _clearImage,
//               child: CircleAvatar(
//                 radius: 10,
//                 backgroundColor: Colors.black54,
//                 child: const Icon(Icons.close, size: 12, color: Colors.white),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   // Helper for the icons
//   Widget _buildAttachmentOption(IconData icon, String label) {
//     return Column(
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         Container(
//           padding: EdgeInsets.all(8),
//           decoration: BoxDecoration(
//             color: Theme.of(context).colorScheme.secondary,
//             borderRadius: BorderRadius.circular(25),
//           ),
//           child: Icon(icon, color: Colors.grey[700], size: 35),
//         ),
//         const SizedBox(height: 5),
//         Text(
//           label,
//           style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
//         ),
//       ],
//     );
//   }
// }

// // SEND BUTTON
// Widget _sendButton(BuildContext context, void Function()? onTap) {
//   return InkWell(
//     onTap: onTap,
//     child: Container(
//       padding: EdgeInsets.all(10),
//       decoration: BoxDecoration(
//         color: Theme.of(context).colorScheme.primary,
//         shape: BoxShape.circle,
//       ),
//       child: Icon(Icons.send, color: Colors.white, size: 24),
//     ),
//   );
// }
// ====================================================================
//                 ORIGINAL CHAT BUBBLE CODE
// ====================================================================
/*
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:social/utils/date_utils.dart';

import 'package:social/widgets/voice_message_bubble.dart';

class ChatBubble extends ConsumerStatefulWidget {
  const ChatBubble({
    super.key,
    required this.alignment,
    required this.isSender,
    required this.data,
    required this.bubbleColor,
    required this.messageId,
    required this.userId,
    required this.senderName,
    required this.receiverId,
    this.isStarred = false,
    this.onReply,
    this.onReplyTap,
    this.isHighlighted = false,
    this.isSelected = false,
    this.onTap,
    required this.onLongPress,
    this.isFirstInSequence = true,
    this.isLastInSequence = true,
  });

  final Alignment alignment;
  final bool isSender;
  final Map<String, dynamic> data;
  final ColorSwatch<int> bubbleColor;
  final String messageId;
  final String userId;
  final String senderName;
  final String receiverId;
  final bool isStarred;
  final void Function()? onReply;
  final void Function(String replyToId)? onReplyTap;
  final bool isHighlighted;
  final bool isSelected;
  final VoidCallback? onTap; // For selection toggle
  final VoidCallback? onLongPress; // For entering selection mode

  // Grouping flags
  final bool isFirstInSequence;
  final bool isLastInSequence;

  @override
  ConsumerState<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends ConsumerState<ChatBubble>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  late AnimationController _animationController;
  late Animation<double> _animation;

  // Swipe threshold to trigger reply
  static const double _swipeThreshold = 35;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      // For sender (right side): swipe left (negative)
      // For receiver (left side): swipe right (positive)
      if (widget.isSender) {
        _dragOffset += details.delta.dx;
        _dragOffset = _dragOffset.clamp(-60.0, 0.0);
      } else {
        _dragOffset += details.delta.dx;
        _dragOffset = _dragOffset.clamp(0.0, 60.0);
      }
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final shouldTriggerReply = widget.isSender
        ? _dragOffset < -_swipeThreshold
        : _dragOffset > _swipeThreshold;

    if (shouldTriggerReply) {
      widget.onReply?.call();
    }

    // Animate back to original position
    _animation = Tween<double>(begin: _dragOffset, end: 0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward(from: 0).then((_) {
      setState(() => _dragOffset = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isImage = widget.data['type'] == 'image';
    bool isVideo = widget.data['type'] == 'video';
    bool isVoice = widget.data['type'] == 'voice';
    bool isMedia = isImage || isVideo;
    final String? caption = widget.data['caption'];
    final textTime = DateUtil.getFormattedTime(widget.data['timestamp']);

    // Check if there's a reply
    final hasReply = widget.data['replyToMessage'] != null;

    // Calculate reply icon opacity based on drag distance
    final replyIconOpacity =
        (widget.isSender
                ? (-_dragOffset / _swipeThreshold)
                : (_dragOffset / _swipeThreshold))
            .clamp(0.0, 1.0);

    // Dynamic Border Radius for grouping effect
    final double largeRadius = 18.0;
    final double smallRadius = 4.0;

    BorderRadius bubbleRadius;
    if (widget.isSender) {
      bubbleRadius = BorderRadius.only(
        topLeft: Radius.circular(largeRadius),
        bottomLeft: Radius.circular(largeRadius),
        topRight: Radius.circular(
          widget.isFirstInSequence ? largeRadius : smallRadius,
        ),
        bottomRight: Radius.circular(
          widget.isLastInSequence ? largeRadius : smallRadius,
        ),
      );
    } else {
      bubbleRadius = BorderRadius.only(
        topRight: Radius.circular(largeRadius),
        bottomRight: Radius.circular(largeRadius),
        topLeft: Radius.circular(
          widget.isFirstInSequence ? largeRadius : smallRadius,
        ),
        bottomLeft: Radius.circular(
          widget.isLastInSequence ? largeRadius : smallRadius,
        ),
      );
    }

    // Dynamic vertical padding
    final double topPad = widget.isFirstInSequence ? 4.0 : 1.0;
    final double bottomPad = widget.isLastInSequence ? 4.0 : 1.0;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final offset = _animationController.isAnimating
            ? _animation.value
            : _dragOffset;

        return Stack(
          alignment: widget.isSender
              ? Alignment.centerLeft
              : Alignment.centerRight,
          children: [
            // Reply icon (appears behind the bubble)
            Opacity(
              opacity: replyIconOpacity,
              child: Padding(
                padding: EdgeInsets.only(
                  left: widget.isSender ? 10 : 0,
                  right: widget.isSender ? 0 : 10,
                ),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.reply,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
              ),
            ),

            // Chat Bubble
            GestureDetector(
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              onLongPress: widget.onLongPress,
              onTap: widget.onTap,
              child: Transform.translate(
                offset: Offset(offset, 0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  alignment: widget.alignment,
                  decoration: BoxDecoration(
                    color: (widget.isHighlighted || widget.isSelected)
                        ? Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: bubbleRadius,
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 8,
                      right: 8,
                      top: topPad,
                      bottom: bottomPad,
                    ),
                    child: Column(
                      crossAxisAlignment: widget.isSender
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        // Bubble
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 250),
                          child: Container(
                            padding: isMedia
                                ? const EdgeInsets.all(4)
                                : const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  widget.bubbleColor.withValues(alpha: 0.9),
                                  Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.8),
                                ],
                                begin: Alignment.bottomLeft,
                                end: Alignment.topRight,
                              ),
                              color: widget.bubbleColor,
                              borderRadius: bubbleRadius,
                            ),
                            child: IntrinsicWidth(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Reply quote if exists
                                  if (hasReply) _buildReplyQuote(context),

                                  isVoice
                                      ? VoiceMessageBubble(
                                          audioUrl: widget.data['message'],
                                          localFilePath:
                                              widget.data['localFilePath'],
                                          duration:
                                              widget.data['voiceDuration'] ?? 0,
                                          isSender: widget.isSender,
                                          bubbleColor: widget.bubbleColor,
                                          textTime: textTime,
                                          status:
                                              widget.data['status'] ?? 'read',
                                          syncStatus: widget.data['syncStatus'],
                                        )
                                      : isMedia
                                      ? _buildMediaContent(
                                          context,
                                          isVideo: isVideo,
                                          caption: caption,
                                          textTime: textTime,
                                        )
                                      : _buildTextContent(context, textTime),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // BUILD REPLY QUOTE (shown inside bubble)
  Widget _buildReplyQuote(BuildContext context) {
    final replyToId = widget.data['replyToId'];
    final replyToSender = widget.data['replyToSender'] ?? '';
    final replyToMessage = widget.data['replyToMessage'] ?? '';
    final replyToType = widget.data['replyToType'] ?? 'text';
    final isMediaReply = replyToType == 'image' || replyToType == 'video';
    final isVoiceReply = replyToType == 'voice';

    String displayMessage;
    if (isVoiceReply) {
      displayMessage = '🎤 Voice message';
    } else if (isMediaReply) {
      displayMessage = '📷 Photo';
    } else {
      displayMessage = replyToMessage;
    }

    return GestureDetector(
      onTap: replyToId != null && widget.onReplyTap != null
          ? () => widget.onReplyTap!(replyToId)
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: widget.isSender
                  ? Colors.white70
                  : Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              replyToSender,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: widget.isSender
                    ? Colors.white
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              displayMessage,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: widget.isSender ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build placeholder for videos without thumbnail
  Widget _buildVideoPlaceholder() {
    return Container(
      height: 300,
      width: 250,
      color: Colors.grey[800],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam, color: Colors.white70, size: 50),
          const SizedBox(height: 8),
          Text('Video', style: TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }

  // BUILD MEDIA CONTENT (Image or Video)
  Widget _buildMediaContent(
    BuildContext context, {
    required bool isVideo,
    required String? caption,
    required String textTime,
  }) {
    final message = widget.data['message'] as String;
    final isGif = message.toLowerCase().contains('.gif');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Media (Image or Video thumbnail)
        Stack(
          children: [
            // Tappable media
            GestureDetector(
              onTap: isVideo
                  ? () => context.push(
                      '/videoPlayer',
                      extra: {'videoUrl': message, 'caption': caption},
                    )
                  : () => context.push(
                      '/viewImage',
                      extra: {
                        'photoUrl': message,
                        'caption': caption,
                        'senderName': widget.isSender
                            ? 'You'
                            : widget.senderName,
                        'timestamp': widget.data['timestamp'],
                      },
                    ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Hero(
                  tag: message,
                  child: isVideo && widget.data['thumbnailUrl'] != null
                      ? CachedNetworkImage(
                          imageUrl: widget.data['thumbnailUrl'],
                          height: 300,
                          width: 250,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Skeleton.replace(
                            height: 300,
                            width: 250,
                            child: Container(
                              color: Colors.transparent.withValues(alpha: 0.4),
                              height: 300,
                              width: 250,
                              child: Center(
                                child: const CircularProgressIndicator(),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) =>
                              _buildVideoPlaceholder(),
                        )
                      : isVideo
                      ? _buildVideoPlaceholder()
                      : (widget.data['localFilePath'] != null &&
                            widget.data['localFilePath'].isNotEmpty)
                      ? (kIsWeb
                            ? Image.network(
                                widget.data['localFilePath'],
                                height: 300,
                                width: 250,
                                fit: BoxFit.cover,
                              )
                            : Image.file(
                                File(widget.data['localFilePath']),
                                height: 300,
                                width: 250,
                                fit: BoxFit.cover,
                              ))
                      : isGif
                      ? Image.network(
                          message,
                          height: 200,
                          width: 220,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                color: Colors.grey[300],
                                height: 200,
                                width: 220,
                                child: const Icon(
                                  Icons.broken_image,
                                  color: Colors.red,
                                ),
                              ),
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Skeleton.replace(
                              height: 200,
                              width: 220,
                              child: Container(
                                height: 200,
                                width: 220,
                                color: Colors.black12,
                              ),
                            );
                          },
                        )
                      : CachedNetworkImage(
                          imageUrl: message,
                          height: 300,
                          width: 250,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Skeleton.replace(
                            height: 300,
                            width: 250,
                            child: Container(
                              color: Colors.transparent.withValues(alpha: 0.4),
                              height: 300,
                              width: 250,
                              child: Center(
                                child: const CircularProgressIndicator(),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            height: 300,
                            width: 250,
                            color: Colors.grey[300],
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.broken_image,
                                  color: Colors.red,
                                  size: 40,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'Failed to load',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),

            // Play button overlay for videos
            if (isVideo)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => context.push(
                    '/videoPlayer',
                    extra: {
                      'videoUrl': widget.data['message'],
                      'caption': caption,
                    },
                  ),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),

            // Time/status overlay (only if no caption)
            if (caption == null || caption.isEmpty)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isStarred)
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: Icon(
                            Icons.star,
                            size: 12,
                            color: Colors.orange,
                          ),
                        ),
                      Text(
                        textTime,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                        ),
                      ),
                      if (widget.isSender) ...[
                        const SizedBox(width: 3),
                        StatusIcon(
                          status: widget.data['status'] ?? 'read',
                          syncStatus: widget.data['syncStatus'],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),

        // Caption (if exists)
        if (caption != null && caption.isNotEmpty)
          Padding(
            padding: EdgeInsetsGeometry.symmetric(horizontal: 4, vertical: 3),
            child: Stack(
              children: [
                Text.rich(
                  TextSpan(
                    text: caption,
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.isSender ? Colors.white : Colors.black,
                    ),
                    children: [const WidgetSpan(child: SizedBox(width: 75))],
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isStarred)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.star,
                            size: 12,
                            color: Colors.orange,
                          ),
                        ),
                      Text(
                        textTime,
                        style: TextStyle(fontSize: 10, color: Colors.white60),
                      ),
                      if (widget.isSender) ...[
                        SizedBox(width: 4),
                        StatusIcon(
                          status: widget.data['status'] ?? 'read',
                          syncStatus: widget.data['syncStatus'],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // BUILD TEXT CONTENT
  Widget _buildTextContent(BuildContext context, String textTime) {
    final bool isEdited = widget.data['isEdited'] == true;

    return SelectionArea(
      child: Stack(
        children: [
          Text.rich(
            TextSpan(
              text: widget.data['message'],
              style: TextStyle(
                fontSize: 14,
                color: widget.isSender ? Colors.white : Colors.black,
              ),
              children: [
                WidgetSpan(child: SizedBox(width: isEdited ? 95 : 75)),
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isStarred)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Icon(Icons.star, size: 12, color: Colors.orange),
                  ),
                if (isEdited)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Text(
                      'edited',
                      style: TextStyle(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: Colors.white60,
                      ),
                    ),
                  ),
                Text(
                  textTime,
                  style: TextStyle(fontSize: 10, color: Colors.white60),
                ),
                if (widget.isSender) ...[
                  SizedBox(width: 3),
                  StatusIcon(
                    status: widget.data['status'] ?? 'read',
                    syncStatus: widget.data['syncStatus'],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
*/
