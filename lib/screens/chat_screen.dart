import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:social/models/message_hive.dart' as hive_model;
import 'package:social/providers/chat_message_provider.dart';
import 'package:social/providers/chat_provider.dart';
import 'package:social/services/auth_service.dart';
import 'package:social/services/notification_service.dart';
import 'package:social/services/sound_service.dart';

import 'package:social/widgets/chat_app_bar.dart';
import 'package:social/widgets/chat_input_bar.dart';
import 'package:social/widgets/liquid_glass.dart';
import 'package:social/widgets/message_list_view.dart';
import 'package:social/widgets/my_alert_dialog.dart';
import 'package:social/widgets/pinned_message.dart';

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
  final authService = AuthService();
  final _notificationService = NotificationService();
  final ScrollController _scrollController = ScrollController();

  // Note: This focus node is currently detached from the input bar's text field.
  // It needs to be connected to ChatInputBar if we want to programmatically focus (e.g. on reply).
  final FocusNode _focusNode = FocusNode();

  final ImagePicker imagePicker = ImagePicker();

  // Reply state
  Map<String, dynamic>? _replyingTo;

  // Highlight state for scroll-to-message
  String? _highlightedMessageId;

  // SELECTION MODE STATE
  final Set<String> _selectedMessageIds = {};
  bool _isSelectionMode = false;
  bool _showScrollToBottom = false;

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final show = _scrollController.offset > 300;
    if (show != _showScrollToBottom) {
      setState(() {
        _showScrollToBottom = show;
      });
    }
  }

  void _enterSelectionMode(String messageId) {
    setState(() {
      _isSelectionMode = true;
      _selectedMessageIds.add(messageId);
    });
  }

  void _toggleSelection(String messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
        if (_selectedMessageIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  // Typing indicator
  Timer? _typingTimer;
  bool _isTyping = false;

  // Helper method to get chat room ID
  String _getChatRoomId(String userId1, String userId2) {
    final ids = [userId1, userId2]..sort();
    return ids.join('_');
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Tell notification service we're in this chat (suppress notifications from this user)
    _notificationService.setCurrentChat(widget.receiverId);
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

  @override
  void dispose() {
    _typingTimer?.cancel();
    if (_isTyping) {
      ref.read(chatServiceProvider).setTypingStatus(widget.receiverId, false);
    }
    _notificationService.clearCurrentChat();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

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

  // Highlight a message. The MessageListView monitors this ID and scrolls to it.
  void _scrollToMessage(String messageId) {
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

  // Set reply to message
  void _setReplyTo(
    Map<String, dynamic> data,
    String messageId,
    String senderName,
  ) {
    setState(() {
      _replyingTo = {
        'messageId': messageId,
        'senderName': senderName,
        'message': data['message'],
        'type': data['type'] ?? 'text',
      };
    });
    _focusNode.requestFocus();
  }

  // Clear reply
  void _clearReply() {
    setState(() {
      _replyingTo = null;
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

  // SET WALLPAPER
  Future<void> _setWallpaper() async {
    try {
      final XFile? pickedFile = await imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      // set wallpaper
      if (pickedFile != null) {
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

  // 2. NEW: SET SOLID COLOR WALLPAPER
  Future<void> _setWallpaperColor(Color color) async {
    try {
      context.pop(); // Close dialog

      // We convert the Color to a Hex String (e.g., "0xFF000000")
      String colorString = '0x${color.value.toRadixString(16).toUpperCase()}';
      await ref
          .read(chatServiceProvider)
          .setChatWallpaperColor(widget.receiverId, colorString);
    } catch (e) {
      _showSnackBar('Failed to set color: $e');
    }
  }

  // 3. NEW: SHOW COLOR PICKER DIALOG (Hex)
  void _showColorPickerDialog() {
    Color pickerColor = Colors.blue;
    // Try to get current wallpaper color
    final chatRoomAsync = ref.read(chatStreamProvider(widget.receiverId));
    if (chatRoomAsync.value?.data() != null) {
      final data = chatRoomAsync.value!.data() as Map<String, dynamic>;
      if (data.containsKey('wallpaper')) {
        final wallpapers = data['wallpaper'] as Map<String, dynamic>?;
        final val = wallpapers?[authService.currentUser!.uid];
        if (val != null && !val.startsWith('http')) {
          try {
            pickerColor = Color(int.parse(val));
          } catch (_) {}
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) {
              pickerColor = color;
            },
            enableAlpha: false,
            displayThumbColor: true,
            hexInputBar: true,
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Save'),
            onPressed: () {
              _setWallpaperColor(pickerColor);
            },
          ),
        ],
      ),
    );
  }

  // RESET WALLPAPER
  Future<void> _resetWallpaper() async {
    try {
      await ref
          .read(chatServiceProvider)
          .deleteChatWallpaper(widget.receiverId);
      _showSnackBar('Chat wallpaper reset!');
    } catch (e) {
      _showSnackBar('Failed to reset wallpaper: $e');
    }
  }

  //  DELETE
  Future<void> _deleteSelectedMessages() async {
    final idsToDelete = List<String>.from(_selectedMessageIds);
    if (idsToDelete.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => MyAlertDialog(
        content: 'Delete ${idsToDelete.length} message(s)?',
        title: 'Delete',
        text: 'Delete',
        onpressed: () async {
          context.pop(); // close dialog
          _exitSelectionMode();

          // Use NOTIFIER to handle Local -> Firestore ID mapping and Hive deletion
          final chatRoomId = _getChatRoomId(
            authService.currentUser!.uid,
            widget.receiverId,
          );
          final notifier = ref.read(chatMessagesProvider(chatRoomId).notifier);

          for (final id in idsToDelete) {
            await notifier.deleteMessage(id);
          }
        },
      ),
    );
  }

  // STAR SELECTED
  Future<void> _starSelectedMessages(
    List<hive_model.Message> allMessages,
  ) async {
    final selectedMsgs = allMessages
        .where((m) => _selectedMessageIds.contains(m.localId))
        .toList();

    _exitSelectionMode();

    final chatService = ref.read(chatServiceProvider);

    for (final msg in selectedMsgs) {
      // Use Firestore ID if available, otherwise fallback to localId (but likely needs sync)
      final idToStar = msg.fireStoreId ?? msg.localId;

      await chatService.toggleStarMessage(
        msg.toFirestoreMap(),
        idToStar,
        widget.receiverId,
      );
    }
  }

  // PIN MESSAGE
  Future<void> _pinSelectedMessage(hive_model.Message message) async {
    _exitSelectionMode();
    await ref.read(chatServiceProvider).pinMessage(widget.receiverId, message);
  }

  // EDIT MESSAGE
  void _editSelectedMessage(hive_model.Message message) {
    if (message.type != 'text') return;
    _exitSelectionMode();

    final TextEditingController editController = TextEditingController(
      text: message.message,
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: editController,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(
            hintText: 'Edit message...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newMessage = editController.text.trim();
              if (newMessage.isNotEmpty && newMessage != message.message) {
                final chatRoomId = _getChatRoomId(
                  authService.currentUser!.uid,
                  widget.receiverId,
                );
                ref
                    .read(chatMessagesProvider(chatRoomId).notifier)
                    .editMessage(message.localId, newMessage);
              }
              context.pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // REPORT MESSAGE
  void _reportMessage(hive_model.Message message) {
    _exitSelectionMode();
    showDialog(
      context: context,
      builder: (context) => MyAlertDialog(
        content: 'Report this message?',
        title: 'Report',
        text: 'Report',
        onpressed: () {
          ref
              .read(chatServiceProvider)
              .reportUser(message.localId, message.senderID);
          context.pop();
          context.pop();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Report sent')));
        },
      ),
    );
  }

  List<Widget> _buildSelectionModeActions(
    String chatRoomId,
    String currentUserId,
  ) {
    // 1. Get Selected Messages from the provider
    final messages =
        ref.watch(chatMessagesProvider(chatRoomId)).asData?.value ?? [];

    final selectedMsgs = messages
        .where((m) => _selectedMessageIds.contains(m.localId))
        .toList();

    if (selectedMsgs.isEmpty) return [];

    final count = selectedMsgs.length;
    final first = selectedMsgs.first;
    final isMe = first.senderID == currentUserId;

    // 2. Define Action List
    final List<Map<String, dynamic>> actions = [];

    // PIN
    final isMedia = first.type == 'image' || first.type == 'video';
    final hasCaption = first.caption != null && first.caption!.isNotEmpty;
    bool canPin = true;
    if (isMedia && !hasCaption) canPin = false;

    if (count == 1 && canPin) {
      actions.add({
        'icon': Icons.push_pin,
        'onTap': () => _pinSelectedMessage(first),
      });
    }

    // DELETE (Always avail in selection)
    actions.add({
      'icon': Icons.delete,
      'onTap': () => _deleteSelectedMessages(),
    });

    // STAR (Always avail)
    actions.add({
      'icon': Icons.star_border,
      'onTap': () => _starSelectedMessages(messages),
    });

    // EDIT
    if (count == 1 && isMe && first.type == 'text') {
      actions.add({
        'icon': Icons.edit,
        'onTap': () => _editSelectedMessage(first),
      });
    }

    // REPORT
    if (count == 1 && !isMe) {
      actions.add({'icon': Icons.flag, 'onTap': () => _reportMessage(first)});
    }

    // 3. Map to Widgets
    return actions.map((action) {
      final isDark = Brightness.dark == Theme.of(context).brightness;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: IconButton(
          icon: Icon(
            action['icon'] as IconData,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: action['onTap'] as VoidCallback,
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // ============ NEW: Listen to Hive-first provider ============
    final currentUserId = authService.currentUser!.uid;
    final chatRoomId = _getChatRoomId(currentUserId, widget.receiverId);

    ref.listen<
      AsyncValue<List<hive_model.Message>>
    >(chatMessagesProvider(chatRoomId), (previous, next) {
      next.whenData((messages) {
        if (!mounted) return;

        // Mark messages as read
        Future.delayed(Duration.zero, () {
          ref
              .read(chatServiceProvider)
              .messageRead(currentUserId, widget.receiverId);
        });

        //  Only scroll if New Messages > Old Messages
        final oldLen = previous?.asData?.value.length ?? 0;
        final newLen = messages.length;

        // Play receive sound if new message is from other user (not initial load)
        if (newLen > oldLen && oldLen > 0 && messages.isNotEmpty) {
          final latestMessage = messages.last;
          if (latestMessage.senderID != currentUserId) {
            SoundService().playReceive();
          }
        }

        // Also scroll if we are nearly at bottom
        // or if it's the first load (oldLen == 0)
        if (newLen > oldLen || oldLen == 0) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scrollController.hasClients) {
              _scrollDown();
            }
          });
        }
      });
    });
    // ============================================================

    final chatRoomAsync = ref.watch(chatStreamProvider(widget.receiverId));

    //  background color for AppBar
    Color? appBarColor;
    if (chatRoomAsync.hasValue) {
      final chatData = chatRoomAsync.value?.data() as Map<String, dynamic>?;
      if (chatData != null && chatData.containsKey('wallpaper')) {
        final wallpapers = chatData['wallpaper'] as Map<String, dynamic>?;
        final wallpaperUrl = wallpapers?[authService.currentUser!.uid];

        if (wallpaperUrl != null && !wallpaperUrl.startsWith('http')) {
          try {
            Color rawColor = Color(int.parse(wallpaperUrl));
            // Darken it significantly (40% towards black) for better legibility and aesthetics
            appBarColor = Color.lerp(rawColor, Colors.black, 0.1);
          } catch (_) {}
        }
      }
    }

    // TextInputField Color
    Color? inputBackgroundColor;
    if (appBarColor != null) {
      // Make input field slightly darker than the app bar for "recessed" depth effect
      inputBackgroundColor = Color.lerp(appBarColor, Colors.black, 0.1);
    } else {
      // Default: Use a translucent dark surface for modern look
      inputBackgroundColor = Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    }

    bool isImageUrl = false;
    String? wallpaperUrl;

    if (chatRoomAsync.value?.data() != null) {
      final chatData = chatRoomAsync.value!.data() as Map<String, dynamic>;
      if (chatData.containsKey('wallpaper')) {
        final wallpapers = chatData['wallpaper'] as Map<String, dynamic>?;
        final currentUserVal = wallpapers?[authService.currentUser!.uid];
        if (currentUserVal is String && currentUserVal.startsWith('http')) {
          isImageUrl = true;
          wallpaperUrl = currentUserVal;
        }
      }
    }

    final backgroundColor = (!isImageUrl && appBarColor != null)
        ? appBarColor.withValues(alpha: 1.0)
        : null;

    // Calculate Navigation Bar Color & Icon Brightness
    Color sysNavBarColor = Theme.of(context).colorScheme.surface;
    Brightness sysNavBarIconBrightness =
        Theme.of(context).brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;

    if (backgroundColor != null) {
      sysNavBarColor = backgroundColor;
      sysNavBarIconBrightness =
          ThemeData.estimateBrightnessForColor(backgroundColor) ==
              Brightness.dark
          ? Brightness.light
          : Brightness.dark;
    } else if (isImageUrl && wallpaperUrl != null) {
      sysNavBarColor = Theme.of(context).colorScheme.surface;
    }

    // Build Actions
    List<Widget> appBarActions;
    if (_isSelectionMode) {
      appBarActions = _buildSelectionModeActions(chatRoomId, currentUserId);
    } else {
      appBarActions = [
        PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'solid_color') {
              _showColorPickerDialog();
            } else if (value == 'reset_wallpaper') {
              await _resetWallpaper();
            } else if (value == 'set_wallpaper') {
              await _setWallpaper();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem<String>(
              value: 'set_wallpaper',
              child: Row(
                children: [
                  Icon(Icons.wallpaper, size: 20),
                  SizedBox(width: 8),
                  Text('Set wallpaper'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'solid_color',
              child: Row(
                children: [
                  Icon(Icons.format_paint_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('Background Color'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'reset_wallpaper',
              child: Text('Reset chat wallpaper'),
            ),
          ],
        ),
      ];
    }

    return Scaffold(
      appBar: ChatAppBar(
        receiverName: widget.receiverName,
        receiverId: widget.receiverId,
        photoUrl: widget.photoUrl,
        backgroundColor: appBarColor,
        isSelectionMode: _isSelectionMode,
        selectedCount: _selectedMessageIds.length,
        actions: appBarActions,
        onProfileTap: () => context.push(
          '/chat_profile/${widget.receiverId}',
          extra: widget.photoUrl,
        ),
      ),
      body: Column(
        children: [
          // PINNED MESSAGE
          if (chatRoomAsync.value?.data() != null)
            Builder(
              builder: (context) {
                final data =
                    chatRoomAsync.value!.data() as Map<String, dynamic>;
                if (data.containsKey('pinnedMessage')) {
                  final pMsg = data['pinnedMessage'] as Map<String, dynamic>?;
                  if (pMsg != null) {
                    return PinnedMessageWidget(
                      color:
                          inputBackgroundColor ??
                          Theme.of(
                            context,
                          ).colorScheme.secondary.withValues(alpha: 0.5),
                      pinnedData: pMsg,
                      receiverId: widget.receiverId,
                      onTap: () {
                        _scrollToMessage(pMsg['id']);
                      },
                    );
                  }
                }
                return SizedBox.shrink();
              },
            ),

          Expanded(
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                systemNavigationBarColor: sysNavBarColor,
                systemNavigationBarIconBrightness: sysNavBarIconBrightness,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color:
                      backgroundColor ?? Theme.of(context).colorScheme.surface,
                  image: (isImageUrl && wallpaperUrl != null)
                      ? DecorationImage(
                          image: CachedNetworkImageProvider(wallpaperUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: Stack(
                  children: [
                    // MESSAGE LIST
                    Positioned.fill(
                      child: MessageListView(
                        chatRoomId: chatRoomId,
                        receiverId: widget.receiverId,
                        receiverName: widget.receiverName,
                        scrollController: _scrollController,
                        isSelectionMode: _isSelectionMode,
                        selectedMessageIds: _selectedMessageIds,
                        onEnterSelectionMode: _enterSelectionMode,
                        onToggleSelection: _toggleSelection,
                        onScrollToMessage: (id) => _scrollToMessage(id),
                        onReply: _setReplyTo,
                        highlightedMessageId: _highlightedMessageId,
                      ),
                    ),

                    // MESSAGE INPUT
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _buildMessageInput(context, inputBackgroundColor),
                    ),

                    // SCROLL BUTTON()
                    if (_showScrollToBottom)
                      Positioned(
                        bottom: 90,
                        right: 15,
                        child: GestureDetector(
                          onTap: _scrollDown,
                          child: LiquidGlass(
                            borderRadius: 30,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(shape: BoxShape.circle),
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // build message input
  Widget _buildMessageInput(BuildContext context, Color? inputBackgroundColor) {
    return ChatInputBar(
      receiverId: widget.receiverId,
      receiverName: widget.receiverName,
      replyingTo: _replyingTo,
      onCancelReply: _clearReply,
      focusNode: _focusNode,
      inputBackgroundColor: inputBackgroundColor,
      onMessageSent: () {
        _setTyping(false);
        _scrollDown();
        _clearReply();
      },
    );
  }
}
