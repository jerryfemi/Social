import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:social/providers/chat_message_provider.dart';
import 'package:social/providers/chat_provider.dart';
import 'package:social/services/auth_service.dart';
import 'package:social/widgets/attachment_picker_sheet.dart';
import 'package:social/widgets/liquid_glass.dart';
import 'package:social/widgets/voice_recorder_button.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class ChatInputBar extends ConsumerStatefulWidget {
  final String receiverId;
  final String receiverName;
  final Map<String, dynamic>? replyingTo;
  final VoidCallback onCancelReply;
  final VoidCallback onMessageSent;
  final FocusNode? focusNode;
  final Color? inputBackgroundColor;

  const ChatInputBar({
    super.key,
    required this.receiverId,
    required this.receiverName,
    required this.replyingTo,
    required this.onCancelReply,
    required this.onMessageSent,
    this.focusNode,
    this.inputBackgroundColor,
  });

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  final _messageController = TextEditingController();
  final authService = AuthService();
  // Use passed focus node or create local fallback
  late FocusNode _focusNode;

  bool _showAttachments = false;
  bool _showEmojiPicker = false;
  bool _isRecording = false;

  // Media State
  final ImagePicker imagePicker = ImagePicker();
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  String? _selectedImagePath;
  String? _selectedMediaType;
  String? _selectedVideoPath;

  // Typing State
  Timer? _typingTimer;
  bool _isTyping = false;
  bool _hasText = false;

  final GlobalKey<VoiceRecorderButtonState> _voiceRecorderKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _messageController.addListener(_onTextChanged);

    // Listen to focus to auto-hide attachments
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      setState(() {
        _showAttachments = false;
      });
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _focusNode.removeListener(_onFocusChange);
    // Only dispose if we created it locally
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }

    // Clear typing status if we leave
    if (_isTyping) {
      ref.read(chatServiceProvider).setTypingStatus(widget.receiverId, false);
    }
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }

    if (_messageController.text.isNotEmpty) {
      _setTyping(true);
    }
  }

  void _setTyping(bool typing) {
    if (typing) {
      if (!_isTyping) {
        _isTyping = true;
        ref.read(chatServiceProvider).setTypingStatus(widget.receiverId, true);
      }
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

  void _toggleAttachments() {
    setState(() {
      _showAttachments = !_showAttachments;
      if (_showAttachments) {
        _focusNode.unfocus();
        _showEmojiPicker = false;
      }
    });
  }

  // Helper method to get chat room ID
  String _getChatRoomId(String userId1, String userId2) {
    final ids = [userId1, userId2]..sort();
    return ids.join('_');
  }

  // SEND MESSAGE
  void _sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty && _selectedImageBytes == null) return;

    final imageBytes = _selectedImageBytes;
    final videoPath = _selectedVideoPath;
    final mediaName = _selectedImageName;
    final isVideo = _selectedMediaType == 'video';

    String? rId;
    String? rMessage;
    String? rSender;
    String? rType;

    if (widget.replyingTo != null) {
      rId = widget.replyingTo!['messageId'];
      rSender = widget.replyingTo!['senderName'];
      rMessage = widget.replyingTo!['message'];
      rType = widget.replyingTo!['type'];
    }

    final currentUserId = authService.currentUser!.uid;
    final chatRoomId = _getChatRoomId(currentUserId, widget.receiverId);
    final notifier = ref.read(chatMessagesProvider(chatRoomId).notifier);

    try {
      if (imageBytes != null) {
        // SEND MEDIA
        await notifier.sendMediaMessage(
          receiverId: widget.receiverId,
          receiverName: widget.receiverName,
          fileName: mediaName ?? (isVideo ? 'video.mp4' : 'image.jpg'),
          imageBytes: isVideo ? null : imageBytes,
          videoPath: isVideo ? videoPath : null,
          imagePath: isVideo ? null : _selectedImagePath,
          caption: text.isNotEmpty ? text : null,
          replyToId: rId,
          replyToMessage: rMessage,
          replyToSender: rSender,
          replyToType: rType ?? 'text',
        );

        _clearImage();
      } else {
        // SEND TEXT
        await notifier.sendTextMessage(
          receiverId: widget.receiverId,
          receiverName: widget.receiverName,
          text: text,
          replyToId: rId,
          replyToMessage: rMessage,
          replyToSender: rSender,
          replyToType: rType ?? 'text',
        );
      }

      _messageController.clear();
      _setTyping(false);

      // Notify parent to clear reply and scroll
      widget.onCancelReply();
      widget.onMessageSent();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // SEND VOICE
  void _sendVoiceMessage(String voicePath, int duration) async {
    String? rId;
    String? rMessage;
    String? rSender;
    String? rType;

    if (widget.replyingTo != null) {
      rId = widget.replyingTo!['messageId'];
      rSender = widget.replyingTo!['senderName'];
      rMessage = widget.replyingTo!['message'];
      rType = widget.replyingTo!['type'];
    }

    final currentUserId = authService.currentUser!.uid;
    final chatRoomId = _getChatRoomId(currentUserId, widget.receiverId);
    final notifier = ref.read(chatMessagesProvider(chatRoomId).notifier);

    try {
      await notifier.sendVoiceMessage(
        receiverId: widget.receiverId,
        receiverName: widget.receiverName,
        localPath: voicePath,
        duration: duration,
        replyToId: rId,
        replyToMessage: rMessage,
        replyToSender: rSender,
        replyToType: rType ?? 'text',
      );

      widget.onCancelReply();
      widget.onMessageSent();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // GIF
  void _sendGifMessage(String url, String? caption) async {
    String? rId;
    String? rMessage;
    String? rSender;
    String? rType;

    if (widget.replyingTo != null) {
      rId = widget.replyingTo!['messageId'];
      rSender = widget.replyingTo!['senderName'];
      rMessage = widget.replyingTo!['message'];
      rType = widget.replyingTo!['type'];
    }

    final currentUserId = authService.currentUser!.uid;
    final chatRoomId = _getChatRoomId(currentUserId, widget.receiverId);
    final notifier = ref.read(chatMessagesProvider(chatRoomId).notifier);

    await notifier.sendTextMessage(
      receiverId: widget.receiverId,
      receiverName: widget.receiverName,
      text: url,
      type: 'image',
      caption: caption,
      replyToId: rId,
      replyToMessage: rMessage,
      replyToSender: rSender,
      replyToType: rType ?? 'text',
    );

    widget.onCancelReply();
    setState(() {
      _showAttachments = false;
      _showEmojiPicker = false;
    });
    _setTyping(false);
    widget.onMessageSent();
  }

  // PICK IMAGE
  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await imagePicker.pickMedia(
        imageQuality: 70,
        requestFullMetadata: false,
      );

      if (pickedFile == null) return;

      String? mime = pickedFile.mimeType;
      if (mime == null || mime.isEmpty) {
        mime = lookupMimeType(pickedFile.path);
      }

      final isImage = mime?.startsWith('image') == true;
      final isVideo = mime?.startsWith('video') == true;

      if (isImage) {
        await _cropImage(pickedFile);
      } else if (isVideo) {
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Unsupported file type')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _cropImage(XFile imageFile) async {
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
          _selectedImagePath = croppedFile.path;
        });
        _focusNode.requestFocus();
      }
    } catch (e) {
      print('Crop error: $e');
    }
  }

  void _clearImage() {
    setState(() {
      _selectedImageBytes = null;
      _selectedImageName = null;
      _selectedVideoPath = null;
      _selectedImagePath = null;
      _selectedMediaType = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // We can infer background color or pass it in.
    // In ChatScreen it was dynamic based on wallpaper.
    // For simplicity, we'll use a default or transparent.
    // If you want strict style matching, we can pass `inputBackgroundColor` as a prop.
    // Let's assume the parent styling handles the background of the screen,
    // and this bar floats. We can use the theme.
    final inputBackgroundColor =
        widget.inputBackgroundColor ??
        Theme.of(context).colorScheme.secondary.withValues(alpha: 0.7);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reply Preview
        if (widget.replyingTo != null) _buildReplyPreview(),

        Padding(
          padding: const EdgeInsets.only(
            bottom: 20,
            left: 15,
            right: 15,
            top: 8,
          ),
          child: _buildNormalInput(context, inputBackgroundColor),
        ),

        // Attachment Drawer
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
                    GestureDetector(
                      onTap: () => _pickImage(),
                      child: _buildAttachmentOption(Icons.image, "Gallery"),
                    ),
                    GestureDetector(
                      onTap: () => _pickImage(),
                      child: _buildAttachmentOption(Icons.camera_alt, "Camera"),
                    ),
                  ],
                ),
              ),
            ),
          ),

        if (_showEmojiPicker)
          AttachmentPickerSheet(
            mesageController: _messageController,
            onSendGif: _sendGifMessage,
          ),
      ],
    );
  }

  Widget _buildReplyPreview() {
    final rSender = widget.replyingTo!['senderName'] ?? '';
    final rMessage = widget.replyingTo!['message'] ?? '';
    final rType = widget.replyingTo!['type'] ?? 'text';

    final isMedia = rType == 'image' || rType == 'video';
    final isVoice = rType == 'voice';

    // We assume 'caption' might be in the 'data' map if we passed the whole map.
    // For simplicity, let's just use what we extracted.

    String messageText;
    if (isVoice) {
      messageText = '🎤 Voice message';
    } else if (isMedia) {
      messageText = '📷 Photo';
    } else {
      messageText = rMessage;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                  rSender,
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
          GestureDetector(
            onTap: widget.onCancelReply,
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

  Widget _buildNormalInput(BuildContext context, Color? inputBackgroundColor) {
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
        if (!_isRecording)
          _selectedImageBytes != null
              ? _buildImageThumbnail()
              : InkWell(
                  borderRadius: BorderRadius.circular(25),
                  onTap: _toggleAttachments,
                  child: LiquidGlass(
                    borderRadius: 30,
                    child: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.secondary.withValues(alpha: 0.2),
                        ),
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
                ),

        const SizedBox(width: 10),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: inputBackgroundColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: TextField(
              focusNode: _focusNode,
              controller: _messageController,
              autocorrect: true,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                filled: false,
                fillColor: Colors.transparent,
                hintText: _selectedImageBytes != null
                    ? 'Add a caption...'
                    : 'Message',
                isDense: true,
                prefixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _showEmojiPicker = !_showEmojiPicker;
                      if (_showEmojiPicker) {
                        _focusNode.unfocus();
                        _showAttachments = false;
                      } else {
                        _focusNode.requestFocus();
                      }
                    });
                  },
                  icon: Icon(Icons.emoji_emotions_outlined),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                border: InputBorder.none,
              ),
            ),
          ),
        ),

        const SizedBox(width: 8),
        if (_hasText || _selectedImageBytes != null)
          _buildSendButton()
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

  Widget _buildAttachmentOption(IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LiquidGlass(
          borderRadius: 25,
          child: Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(25)),
            child: Icon(icon, color: Colors.white, size: 35),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSendButton() {
    return InkWell(
      onTap: _sendMessage,
      child: LiquidGlass(
        borderRadius: 30,
        child: Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(shape: BoxShape.circle),
          child: Icon(Icons.send, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}
