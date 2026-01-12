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
import 'package:social/providers/chat_provider.dart';
import 'package:social/utils/date_utils.dart';
import 'package:social/widgets/chat_bubble.dart';
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
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _showAttachments = false;
  final ImagePicker imagePicker = ImagePicker();
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  String? _selectedMediaType;
  String? _selectedVideoPath;

  @override
  void initState() {
    super.initState();
    // scroll down if focusNode has focus
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() {
          _showAttachments = false;
        });
        Future.delayed(Duration(milliseconds: 300), () => _scrollDown());
      }
    });
  }

  // dispose
  @override
  void dispose() {
    super.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _messageController.dispose();
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

  // send message
  void sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty && _selectedImageBytes == null) return;

    final imageBytes = _selectedImageBytes;
    final videoPath = _selectedVideoPath;
    final mediaName = _selectedImageName;
    final isVideo = _selectedMediaType == 'video';

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
            );
      }

      // clear textfield
      _messageController.clear();

      // scroll down after sending mesage
      _scrollDown();
    } catch (e) {
      _showSnackBar('Error: $e');
    }
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

        Future.delayed(Duration.zero, () {
          ref
              .read(chatServiceProvider)
              .messageRead(authService.currentUser!.uid, widget.receiverId);
        });
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
              Text(
                widget.receiverName,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
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

    return Padding(
      padding: const EdgeInsets.only(left: 15, right: 15, top: 5),
      child: messageAsync.when(
        error: (error, stackTrace) => const Center(child: Text('Error:')),
        loading: () => _buildSkeletonMessages(),
        data: (snapShot) {
          final message = snapShot.docs.reversed.toList();

          // empty state
          if (message.isEmpty) {
            return const Center(child: Text('No Messages yet'));
          }

          // Filter out messages deleted for current user
          final currentUserId = authService.currentUser!.uid;
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
        },
      ),
    );
  }

  // BUILD SKELETON MESSAGES FOR LOADING STATE
  Widget _buildSkeletonMessages() {
    return ListView.builder(
      itemCount: 12,
      itemBuilder: (context, index) {
        final isSender = index % 2 == 0;
        return Skeletonizer(
          enabled: true,
          child: Container(
            alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
            padding: const EdgeInsets.all(8.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 250),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isSender
                      ? 'Loading message text...'
                      : 'Loading reply message...',
                ),
              ),
            ),
          ),
        );
      },
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

    return ChatBubble(
      senderName: name,
      messageId: doc.id,
      userId: data['senderID'],
      alignment: alignment,
      isSender: isSender,
      data: data,
      bubbleColor: bubbleColor,
      receiverId: widget.receiverId,
      isStarred: isStarred,
    );
  }

  // build message input
  Widget _buildMessageInput(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.only(
            top: 10,
            bottom: 20,
            left: 15,
            right: 15,
          ),
          decoration: BoxDecoration(),
          child: Row(
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
              // TEXT FIELD
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  focusNode: _focusNode,
                  controller: _messageController,
                  autocorrect: true,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => sendMessage(),
                  decoration: InputDecoration(
                    filled: true,
                    suffixIcon: _sendButton(context, sendMessage),

                    hintText: _selectedImageBytes != null
                        ? 'Add a caption...'
                        : null,
                    isDense: true,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.secondary,
                        width: 2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.secondary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 2. THE ATTACHMENT DRAWER
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
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Container(
        padding: EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
      ),
    ),
  );
}
