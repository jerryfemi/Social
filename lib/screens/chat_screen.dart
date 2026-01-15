import 'dart:async';
import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:social/models/message.dart';
import 'package:social/services/auth_service.dart';
import 'package:social/services/cache_service.dart';
import 'package:social/services/notification_service.dart';
import 'package:social/providers/chat_provider.dart';
import 'package:social/utils/date_utils.dart';
import 'package:social/widgets/chat_bubble.dart';
import 'package:social/widgets/voice_recorder_button.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String receiverName;
  final String receiverId;
  final String? photoUrl;
  const ChatScreen({
    super.key,
    required this.receiverName,
    required this.receiverId,
    required this.photoUrl,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final authService = AuthService();
  final _notificationService = NotificationService();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _showAttachments = false;
  final ImagePicker imagePicker = ImagePicker();
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  String? _selectedMediaType;
  String? _selectedVideoPath;

  // Reply state
  Map<String, dynamic>? _replyingTo;
  String? _replyingToId;
  String? _replyingToSender;

  // Voice recording state
  bool _isRecording = false;
  final GlobalKey<VoiceRecorderButtonState> _voiceRecorderKey = GlobalKey();

  // Track if text field has content
  bool _hasText = false;

  // Highlight state for scroll-to-message
  String? _highlightedMessageId;
  final Map<String, GlobalKey> _messageKeys = {};

  // Cache debounce - only cache once per session unless messages change
  int _lastCachedMessageCount = 0;

  // Typing indicator
  Timer? _typingTimer;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();

    // Tell notification service we're in this chat (suppress notifications from this user)
    _notificationService.setCurrentChat(widget.receiverId);

    // scroll down if focusNode has focus
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() {
          _showAttachments = false;
        });
        Future.delayed(Duration(milliseconds: 300), () => _scrollDown());
      }
      // Trigger rebuild when focus changes
      setState(() {});
    });

    // Listen for text changes and update typing status
    _messageController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }

    // Update typing status
    if (_messageController.text.isNotEmpty) {
      _setTyping(true);
    }
  }

  void _setTyping(bool typing) {
    if (typing) {
      // Set typing to true
      if (!_isTyping) {
        _isTyping = true;
        ref.read(chatServiceProvider).setTypingStatus(widget.receiverId, true);
      }

      // Reset the timer
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _isTyping = false;
        ref.read(chatServiceProvider).setTypingStatus(widget.receiverId, false);
      });
    } else {
      _typingTimer?.cancel();
      _isTyping = false;
      ref.read(chatServiceProvider).setTypingStatus(widget.receiverId, false);
    }
  }

  // dispose
  @override
  void dispose() {
    // Clear typing status
    _typingTimer?.cancel();
    if (_isTyping) {
      ref.read(chatServiceProvider).setTypingStatus(widget.receiverId, false);
    }
    // Clear current chat so notifications show again
    _notificationService.clearCurrentChat();
    _focusNode.dispose();
    _scrollController.dispose();
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    super.dispose();
  }

  void _toggleAttachments() {
    setState(() {
      _showAttachments = !_showAttachments;
      if (_showAttachments) {
        // close keyboard
        _focusNode.unfocus();
      }
    });

    // Scroll to bottom after menu opens
    if (_showAttachments) {
      Future.delayed(const Duration(milliseconds: 300), () => _scrollDown());
    }
  }

  // scroll down
  void _scrollDown({bool immediate = false}) {
    if (_scrollController.hasClients) {
      if (immediate) {
        _scrollController.jumpTo(0.0);
      } else {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  // Format last seen timestamp
  String _formatLastSeen(dynamic timestamp) {
    DateTime lastSeenTime;

    if (timestamp is Timestamp) {
      lastSeenTime = timestamp.toDate();
    } else if (timestamp is int) {
      lastSeenTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else {
      return '';
    }

    final now = DateTime.now();
    final difference = now.difference(lastSeenTime);

    if (difference.inMinutes < 1) {
      return 'Last seen just now';
    } else if (difference.inMinutes < 60) {
      return 'Last seen ${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return 'Last seen ${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Last seen yesterday';
    } else if (difference.inDays < 7) {
      return 'Last seen ${difference.inDays}d ago';
    } else {
      return 'Last seen ${lastSeenTime.day}/${lastSeenTime.month}/${lastSeenTime.year}';
    }
  }

  // Scroll to a specific message and highlight it
  void _scrollToMessage(String messageId) {
    final key = _messageKeys[messageId];
    if (key?.currentContext != null) {
      // Scroll to the message
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.5, // Center the message
      );

      // Highlight the message briefly
      setState(() {
        _highlightedMessageId = messageId;
      });

      // Remove highlight after animation
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          setState(() {
            _highlightedMessageId = null;
          });
        }
      });
    }
  }

  // send message
  void sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty && _selectedImageBytes == null) return;

    final imageBytes = _selectedImageBytes;
    final videoPath = _selectedVideoPath;
    final mediaName = _selectedImageName;
    final isVideo = _selectedMediaType == 'video';

    // Capture reply data before clearing
    final replyToId = _replyingToId;
    final replyToMessage = _replyingTo?['message'] as String?;
    final replyToSender = _replyingToSender;
    final replyToType = _replyingTo?['type'] as String? ?? 'text';

    try {
      if (imageBytes != null) {
        // SEND MEDIA
        ref
            .read(chatServiceProvider)
            .sendMediaMessage(
              widget.receiverId,
              mediaName ?? (isVideo ? 'video.mp4' : 'image.jpg'),
              imageBytes: isVideo ? null : imageBytes,
              videoPath: isVideo ? videoPath : null,
              caption: text.isNotEmpty ? text : null,
              replyToId: replyToId,
              replyToMessage: replyToMessage,
              replyToSender: replyToSender,
              replyToType: replyToType,
            )
            .catchError((e) {});
        _clearImage();
      } else {
        // send message
        ref
            .read(chatServiceProvider)
            .sendMessage(
              widget.receiverId,
              _messageController.text.trim(),
              MessageStatus.sent,
              replyToId: replyToId,
              replyToMessage: replyToMessage,
              replyToSender: replyToSender,
              replyToType: replyToType,
            );
      }

      // clear textfield and reply
      _messageController.clear();
      _clearReply();
      _setTyping(false); // Clear typing status when message sent

      // scroll down after sending mesage
      _scrollDown();
    } catch (e) {
      _showSnackBar('Error: $e');
    }
  }

  // Send voice message
  void _sendVoiceMessage(String voicePath, int duration) async {
    // Capture reply data before clearing
    final replyToId = _replyingToId;
    final replyToMessage = _replyingTo?['message'] as String?;
    final replyToSender = _replyingToSender;
    final replyToType = _replyingTo?['type'] as String? ?? 'text';

    try {
      await ref
          .read(chatServiceProvider)
          .sendVoiceMessage(
            widget.receiverId,
            voicePath,
            duration,
            replyToId: replyToId,
            replyToMessage: replyToMessage,
            replyToSender: replyToSender,
            replyToType: replyToType,
          );

      // Clear reply
      _clearReply();

      // Scroll down after sending
      _scrollDown();
    } catch (e) {
      _showSnackBar('Error sending voice message: $e');
    }
  }

  // Set reply to message
  void _setReplyTo(
    Map<String, dynamic> data,
    String messageId,
    String senderName,
  ) {
    setState(() {
      _replyingTo = data;
      _replyingToId = messageId;
      _replyingToSender = senderName;
    });
    _focusNode.requestFocus();
  }

  // Clear reply
  void _clearReply() {
    setState(() {
      _replyingTo = null;
      _replyingToId = null;
      _replyingToSender = null;
    });
  }

  // show snackbar
  void _showSnackBar(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(title, style: TextStyle()),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // pick and send image
  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await imagePicker.pickMedia(
        imageQuality: 70,
        requestFullMetadata: false,
      );

      if (pickedFile == null) {
        print('No file selected');
        return;
      }

      // On web, use mimeType property; on mobile, use lookupMimeType
      String? mime = pickedFile.mimeType;
      if (mime == null || mime.isEmpty) {
        mime = lookupMimeType(pickedFile.path);
      }

      print('Picked file: ${pickedFile.name}, mime: $mime');

      final isImage = mime?.startsWith('image') == true;
      final isVideo = mime?.startsWith('video') == true;

      if (isImage) {
        print('Image picked');

        // On mobile, use image cropper
        await cropImage(pickedFile);

        print('IMAGE READY 🟢');
      } else if (isVideo) {
        print('Video picked');

        // On mobile, use video trimmer
        if (!mounted) return;
        final String? trimmedPath = await context.push(
          '/editVideo',
          extra: pickedFile.path,
        );

        if (trimmedPath != null) {
          final Uint8List? thumbBytes = await VideoThumbnail.thumbnailData(
            video: trimmedPath,
            imageFormat: ImageFormat.JPEG,
            quality: 75,
          );

          setState(() {
            _selectedImageBytes = thumbBytes;
            _selectedVideoPath = trimmedPath;
            _selectedMediaType = 'video';
            _showAttachments = false;
          });
        }
      } else {
        print('Unknown media type: $mime');
        _showSnackBar('Unsupported file type');
      }
    } catch (e) {
      print('Error picking image: $e');
      _showSnackBar('Error: $e');
    }
  }

  // CROP IMAGE
  Future<void> cropImage(XFile imageFile) async {
    try {
      final CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarColor: Theme.of(context).colorScheme.secondary,
            toolbarWidgetColor: Theme.of(context).colorScheme.primary,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
          WebUiSettings(context: context),
        ],
      );

      if (croppedFile != null) {
        final bytes = await croppedFile.readAsBytes();

        setState(() {
          _selectedImageBytes = bytes;
          _selectedImageName = imageFile.name;
        });
        _focusNode.requestFocus();
      }
      print('IMAGE CROP SUCCESSFUL 🟢 ');
    } catch (e) {
      print('FAILED TO CROP IMAGE🔴: $e');
    }
  }

  void _clearImage() {
    setState(() {
      _selectedImageBytes = null;
      _selectedImageName = null;
      _selectedVideoPath = null;
      _selectedMediaType = null;
    });
  }

  // SET WALLPAPER
  Future<void> _setWallpaper() async {
    try {
      final XFile? pickedFile = await imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      // set wallpaper
      if (pickedFile != null) {
        setState(() => _showAttachments = false);

        Uint8List filebytes = await pickedFile.readAsBytes();
        String fileName = pickedFile.name;

        // set wallpaper
        await ref
            .read(chatServiceProvider)
            .setChatWallpaper(widget.receiverId, filebytes, fileName);

        _showSnackBar('Wallpaper set!');
      }
    } catch (e) {
      _showSnackBar('Failed to set wallpaper: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<QuerySnapshot>>(messageProvider(widget.receiverId), (
      previous,
      next,
    ) {
      next.whenData((snapshot) {
        if (!mounted) return;

        // Mark messages as read
        Future.delayed(Duration.zero, () {
          ref
              .read(chatServiceProvider)
              .messageRead(authService.currentUser!.uid, widget.receiverId);
        });

        // Cache messages for offline viewing (only if count changed)
        if (snapshot.docs.isNotEmpty &&
            snapshot.docs.length != _lastCachedMessageCount) {
          _lastCachedMessageCount = snapshot.docs.length;
          final currentUserId = authService.currentUser!.uid;
          final messagesToCache = snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {...data, 'docId': doc.id};
          }).toList();
          CacheService.cacheChatMessages(
            currentUserId,
            widget.receiverId,
            messagesToCache,
          );
        }
      });

      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollDown();
        }
      });
    });

    final chatRoomAsync = ref.watch(chatStreamProvider(widget.receiverId));

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => context.push(
            '/chat_profile/${widget.receiverId}',
            extra: widget.photoUrl,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: widget.photoUrl != null && widget.photoUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: widget.photoUrl!,
                        height: 44,
                        width: 44,
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
                        radius: 22,
                        child: Icon(
                          Icons.person,
                          size: 20,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      ),
              ),
              SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.receiverName,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  // Typing indicator or Online status
                  Consumer(
                    builder: (context, ref, child) {
                      final typingAsync = ref.watch(
                        typingStatusProvider(widget.receiverId),
                      );
                      final onlineAsync = ref.watch(
                        onlineStatusProvider(widget.receiverId),
                      );
                      final isTyping = typingAsync.value ?? false;
                      final onlineData = onlineAsync.value;
                      final isOnline = onlineData?['isOnline'] ?? false;

                      // Priority: typing > online > last seen
                      if (isTyping) {
                        return Text(
                          'typing...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.primary,
                            fontStyle: FontStyle.italic,
                          ),
                        );
                      }

                      if (isOnline) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Active now',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        );
                      }

                      // Show last seen if not online
                      final lastSeen = onlineData?['lastSeen'];
                      if (lastSeen != null) {
                        return Text(
                          _formatLastSeen(lastSeen),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        );
                      }

                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: chatRoomAsync.when(
        error: (error, stackTrace) =>
            Center(child: Text('Error fetching chats $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
        data: (snapShot) {
          final chatData = snapShot.data() as Map<String, dynamic>?;
          String? wallpaperUrl;

          print('CHAT DATA : $chatData');
          //  CHECK IF DATA AND WALLPAPERS EXIST
          if (chatData != null && chatData.containsKey('wallpaper')) {
            final wallpapers = chatData['wallpaper'] as Map<String, dynamic>?;
            wallpaperUrl = wallpapers?[authService.currentUser!.uid];

            print('FOUND WALLPAPER URL : $wallpaperUrl');
          }
          return Container(
            decoration: BoxDecoration(
              image: wallpaperUrl != null
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(wallpaperUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: Column(
              children: [
                // display messages
                Expanded(child: _buildMessageList()),
                _buildMessageInput(context),
              ],
            ),
          );
        },
      ),
    );
  }

  // build message list
  Widget _buildMessageList() {
    final messageAsync = ref.watch(messageProvider(widget.receiverId));
    final cachedMessages = ref.watch(cachedMessagesProvider(widget.receiverId));

    return Padding(
      padding: const EdgeInsets.only(left: 15, right: 15, top: 5),
      child: Builder(
        builder: (context) {
          final cached = cachedMessages.value;

          // Only show skeleton when truly no data (not in cache)
          if (messageAsync.isLoading &&
              !messageAsync.hasValue &&
              (cached == null || cached.isEmpty)) {
            return _buildSkeletonMessages();
          }

          final snapshot = messageAsync.value;
          final error = messageAsync.error;

          // If we have live data, use it
          if (snapshot != null && snapshot.docs.isNotEmpty) {
            final currentUserId = authService.currentUser!.uid;
            final message = snapshot.docs.reversed.toList();

            // Filter out messages deleted for current user
            final filteredMessages = message.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final List<dynamic> deletedFor = data['deletedFor'] ?? [];
              return !deletedFor.contains(currentUserId);
            }).toList();

            if (filteredMessages.isEmpty) {
              return const Center(child: Text('No Messages yet'));
            }

            return ListView.builder(
              reverse: true,
              controller: _scrollController,
              itemBuilder: (context, index) {
                return _buildMessageItemWithDate(
                  filteredMessages,
                  index,
                  context,
                );
              },
              itemCount: filteredMessages.length,
            );
          }

          // Fall back to cached data while loading
          if (cached != null && cached.isNotEmpty) {
            final currentUserId = authService.currentUser!.uid;
            final reversedCached = cached.reversed.toList();

            // Filter out messages deleted for current user
            final filteredCached = reversedCached.where((msg) {
              final List<dynamic> deletedFor = msg['deletedFor'] ?? [];
              return !deletedFor.contains(currentUserId);
            }).toList();

            if (filteredCached.isEmpty) {
              return const Center(child: Text('No Messages yet'));
            }

            return ListView.builder(
              reverse: true,
              controller: _scrollController,
              itemBuilder: (context, index) {
                return _buildCachedMessageItem(filteredCached, index, context);
              },
              itemCount: filteredCached.length,
            );
          }

          if (error != null) {
            return const Center(child: Text('Error loading messages'));
          }

          return const Center(child: Text('No Messages yet'));
        },
      ),
    );
  }

  // Build message item from cached data
  Widget _buildCachedMessageItem(
    List<Map<String, dynamic>> messages,
    int index,
    BuildContext context,
  ) {
    final data = messages[index];
    final bool isSender = data['senderID'] == authService.currentUser!.uid;
    final messageId = data['docId'] ?? '';

    // Convert timestamp from milliseconds if needed
    dynamic timestamp = data['timestamp'];
    if (timestamp is int) {
      timestamp = Timestamp.fromMillisecondsSinceEpoch(timestamp);
    }

    final messageData = {...data, 'timestamp': timestamp};

    // Store key for scroll-to-message
    _messageKeys[messageId] = GlobalKey();

    // Show date header if needed
    Widget? dateHeader;
    if (index == messages.length - 1 ||
        !_isSameDay(
          messages[index]['timestamp'],
          messages[index + 1]['timestamp'],
        )) {
      dateHeader = _buildDateHeader(timestamp);
    }

    return Column(
      key: _messageKeys[messageId],
      children: [
        if (dateHeader != null) dateHeader,
        ChatBubble(
          userId: data['senderID'] ?? '',
          senderName: isSender ? 'You' : widget.receiverName,
          alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
          isSender: isSender,
          data: messageData,
          bubbleColor: isSender ? Colors.purpleAccent : Colors.grey,
          messageId: messageId,
          receiverId: widget.receiverId,
          isHighlighted: _highlightedMessageId == messageId,
          onReplyTap: (replyToId) => _scrollToMessage(replyToId),
          onReply: () => _setReplyTo(
            messageData,
            messageId,
            isSender ? 'You' : widget.receiverName,
          ),
        ),
      ],
    );
  }

  // Helper to check if two timestamps are on the same day
  bool _isSameDay(dynamic ts1, dynamic ts2) {
    DateTime d1, d2;
    if (ts1 is int) {
      d1 = DateTime.fromMillisecondsSinceEpoch(ts1);
    } else if (ts1 is Timestamp) {
      d1 = ts1.toDate();
    } else {
      return false;
    }
    if (ts2 is int) {
      d2 = DateTime.fromMillisecondsSinceEpoch(ts2);
    } else if (ts2 is Timestamp) {
      d2 = ts2.toDate();
    } else {
      return false;
    }
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  // BUILD SKELETON MESSAGES FOR LOADING STATE
  Widget _buildSkeletonMessages() {
    return Skeletonizer(
      enabled: true,
      child: ListView.builder(
        itemCount: 10,
        itemBuilder: (context, index) {
          final isSender = index % 2 == 0;
          return ChatBubble(
            alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
            isSender: isSender,
            data: {
              'message': BoneMock.paragraph,
              'timestamp': Timestamp.now(),
              'type': 'text',
              'status': 'read',
            },
            bubbleColor: isSender ? Colors.purpleAccent : Colors.grey,
            messageId: '',
            userId: '',
            senderName: '',
            receiverId: '',
          );
        },
      ),
    );
  }

  Widget _buildMessageItemWithDate(
    List<QueryDocumentSnapshot> docs,
    int index,
    BuildContext context,
  ) {
    final doc = docs[index];
    final data = doc.data() as Map<String, dynamic>;

    // get timestamp
    Timestamp t = data['timestamp'];
    DateTime messageDate = t.toDate();

    bool showHeader = false;

    // if its the last message ever show header
    if (index == docs.length - 1) {
      showHeader = true;
    } else {
      // otherwise check next message (which is older)
      final nextDoc = docs[index + 1];
      final nextData = nextDoc.data() as Map<String, dynamic>;
      Timestamp nextT = nextData['timestamp'];
      DateTime nextDate = nextT.toDate();

      // if days are different show header
      if (!DateUtil.isSameDay(messageDate, nextDate)) {
        showHeader = true;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) _buildDateHeader(messageDate),
        _buildMessageItem(doc, context),
      ],
    );
  }

  // build date header
  Widget _buildDateHeader(DateTime date) {
    return Center(
      child: Container(
        padding: const EdgeInsetsGeometry.symmetric(
          vertical: 6,
          horizontal: 12,
        ),
        margin: EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(DateUtil.getDateLabel(date)),
      ),
    );
  }

  // build message item list
  Widget _buildMessageItem(DocumentSnapshot doc, BuildContext context) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    bool isSender = data['senderID'] == authService.currentUser!.uid;

    //  Align based on sender
    var alignment = isSender ? Alignment.centerRight : Alignment.centerLeft;

    //  Color formatting to make it easier to see
    var bubbleColor = isSender ? Colors.purpleAccent : Colors.grey;

    final name = isSender ? 'You' : widget.receiverName;

    final starredAsync = ref.watch(starredMessagesProvider);
    final starredIds = starredAsync.value?.docs.map((e) => e.id).toSet() ?? {};
    final isStarred = starredIds.contains(doc.id);

    // Get or create a GlobalKey for this message
    _messageKeys.putIfAbsent(doc.id, () => GlobalKey());

    return ChatBubble(
      key: _messageKeys[doc.id],
      senderName: name,
      messageId: doc.id,
      userId: data['senderID'],
      alignment: alignment,
      isSender: isSender,
      data: data,
      bubbleColor: bubbleColor,
      receiverId: widget.receiverId,
      isStarred: isStarred,
      isHighlighted: _highlightedMessageId == doc.id,
      onReply: () => _setReplyTo(data, doc.id, name),
      onReplyTap: _scrollToMessage,
    );
  }

  // build message input
  Widget _buildMessageInput(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 20, left: 15, right: 15),
          child: _buildNormalInput(context),
        ),

        // 2. THE ATTACHMENT DRAWER (hidden when recording)
        if (!_isRecording)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            height: _showAttachments ? 120 : 0,
            width: double.infinity,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Container(
                height: 120,
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // gallery buttpn
                    GestureDetector(
                      onTap: () => _pickImage(),
                      child: _buildAttachmentOption(Icons.image, "Gallery"),
                    ),

                    // camera button
                    GestureDetector(
                      onTap: () => _pickImage(),
                      child: _buildAttachmentOption(Icons.camera_alt, "Camera"),
                    ),

                    // wallpaper button
                    GestureDetector(
                      onTap: () => _setWallpaper(),
                      child: _buildAttachmentOption(
                        Icons.wallpaper_rounded,
                        "Wallpaper",
                      ),
                    ),
                    _buildAttachmentOption(Icons.person_pin_rounded, "Contact"),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // REPLY PREVIEW WIDGET (inside TextField)
  Widget _buildReplyPreview() {
    final type = _replyingTo!['type'];
    final isMedia = type == 'image' || type == 'video';
    final isVoice = type == 'voice';

    String messageText;
    if (isVoice) {
      messageText = '🎤 Voice message';
    } else if (isMedia) {
      messageText = _replyingTo!['caption'] ?? '📷 Photo';
    } else {
      messageText = _replyingTo!['message'];
    }

    return Container(
      margin: const EdgeInsets.only(left: 8, right: 8, top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _replyingToSender ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  messageText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          // Close button
          GestureDetector(
            onTap: _clearReply,
            child: Icon(
              Icons.close,
              size: 18,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  // Normal input (text field + plus button)
  Widget _buildNormalInput(BuildContext context) {
    // When recording, show only the VoiceRecorderButton (expanded)
    if (_isRecording) {
      return VoiceRecorderButton(
        key: _voiceRecorderKey,
        onRecordingComplete: (path, duration) {
          setState(() => _isRecording = false);
          _sendVoiceMessage(path, duration);
        },
        onRecordingStart: () {},
        onRecordingCancel: () => setState(() => _isRecording = false),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _selectedImageBytes != null
            // selected image preview
            ? _buildImageThumbnail()
            :
              // PLUS BUTTON
              InkWell(
                borderRadius: BorderRadius.circular(25),
                onTap: _toggleAttachments,
                child: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary,
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedRotation(
                    turns: _showAttachments ? 0.125 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.add,
                      size: 26,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),

        const SizedBox(width: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color:
                  Theme.of(context).inputDecorationTheme.fillColor ??
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.secondary,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reply preview
                if (_replyingTo != null) _buildReplyPreview(),
                // Text field
                TextField(
                  focusNode: _focusNode,
                  controller: _messageController,
                  autocorrect: true,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardType: TextInputType.multiline,
                  maxLines: 5,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.transparent,
                    hintText: _selectedImageBytes != null
                        ? 'Add a caption...'
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    border: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Voice recorder or send button
        const SizedBox(width: 8),
        if (_hasText || _selectedImageBytes != null)
          _sendButton(context, sendMessage)
        else
          VoiceRecorderButton(
            key: _voiceRecorderKey,
            onRecordingComplete: _sendVoiceMessage,
            onRecordingStart: () => setState(() => _isRecording = true),
            onRecordingCancel: () => setState(() => _isRecording = false),
          ),
      ],
    );
  }

  //  THUMBNAIL WIDGET
  Widget _buildImageThumbnail() {
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: () => _pickImage(),
            child: Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 2),
                image: DecorationImage(
                  image: MemoryImage(_selectedImageBytes!),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

          // cancel button
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              onTap: _clearImage,
              child: CircleAvatar(
                radius: 10,
                backgroundColor: Colors.black54,
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper for the icons
  Widget _buildAttachmentOption(IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondary,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Icon(icon, color: Colors.grey[700], size: 35),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

// SEND BUTTON
Widget _sendButton(BuildContext context, void Function()? onTap) {
  return InkWell(
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.send, color: Colors.white, size: 24),
    ),
  );
}
