import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide Message;
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:social/firebase_options.dart';
import 'package:social/models/message_hive.dart';
import 'package:social/services/hive_service.dart';
import 'package:social/services/sound_service.dart';
import 'package:social/utils/router.dart';

// ============ 1. BACKGROUND HANDLER (MUST BE TOP-LEVEL) ============
// This runs in a separate "Isolate" (like a mini-app) when the app is closed.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 1. Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("🌙 BACKGROUND PAYLOAD: ${message.data}");

  // CHECK: If no user is logged in (or token invalid), don't process
  // Note: In background isolate, FirebaseAuth.currentUser might need reload or might be null if signed out.
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) {
    debugPrint("🌙 Background: No user logged in, ignoring message.");
    return;
  }

  // 2. Initialize Hive (Critical for offline saving)
  await Hive.initFlutter();

  // Register Adapters (Ensure these match your main.dart)
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(MessageAdapter());
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(MessageSyncStatusAdapter());
  }

  try {
    final data = message.data;

    // Extract info
    final senderId = data['senderID'] as String?;
    final receiverId = data['receiverID'] as String?;

    // SECURITY CHECK: Ensure this message is meant for the signed-in user
    if (receiverId != currentUser.uid) {
      debugPrint(
        "🌙 Background: Message for $receiverId but logged in as ${currentUser.uid}. Ignoring.",
      );
      return;
    }

    if (senderId != null && receiverId != null) {
      // Construct chat room ID
      final ids = [senderId, receiverId]..sort();
      final chatRoomId = ids.join('_');

      final msg = Message.fromNotification(data);

      // Use the helper to open, write, and close strictly
      final box = await Hive.openBox<Message>('chat_$chatRoomId');
      await box.put(msg.localId, msg);
      await box.close();

      debugPrint(
        '🌙 Background: Message saved to Hive! User will see it instantly.',
      );
    }
  } catch (e) {
    debugPrint('❌ Background handler failed: $e');
  }
}

// ============ 2. NOTIFICATION SERVICE CLASS ============
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _fireStore = FirebaseFirestore.instance;

  String? _currentChatUserId;
  Map<String, dynamic>? _pendingNotificationData;
  bool _isInitialized = false;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final AndroidNotificationChannel _channel = const AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.max,
  );

  void setCurrentChat(String? userId) {
    _currentChatUserId = userId;
  }

  void clearCurrentChat() {
    _currentChatUserId = null;
  }

  Future<void> clearAllNotifications() async {
    try {
      await _localNotifications.cancelAll();
    } catch (e) {
      debugPrint(
        'Failed to clear notifications (likely unsupported on this platform): $e',
      );
    }
  }

  Future<void> initNotifications() async {
    if (_isInitialized) return;
    _isInitialized = true;

    await _requestPermission();
    await _getToken();
    await _setupForegroundNotifications();

    // 1. Background/Terminated Handler Registration is done in main.dart
    // But we handle the "App Opened" logic here.

    // 2. Handle Tap: Background -> Foreground
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    // 3. Handle Tap: Terminated -> Foreground
    RemoteMessage? initialMessage = await _firebaseMessaging
        .getInitialMessage();
    if (initialMessage != null) {
      debugPrint('🚀 App launched from notification');
      _pendingNotificationData = initialMessage.data;
    }

    // 4. Handle Foreground Messages (Heads-up display)
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  void processPendingNotification() {
    if (_pendingNotificationData != null) {
      final data = _pendingNotificationData!;
      _pendingNotificationData = null;
      // Wait slightly for Router to be ready
      Future.delayed(const Duration(milliseconds: 500), () {
        _navigateFromData(data);
      });
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    // Save to Hive immediately so UI updates even if we don't tap
    // Note: We use the BackgroundHandler logic here effectively by calling HiveService

    debugPrint("🌙 ForeGROUND PAYLOAD: ${message.data}");
    try {
      final data = message.data;
      final senderId = data['senderID'];
      final receiverId = data['receiverID']; // Ensure your payload has this

      if (senderId != null && receiverId != null) {
        final ids = [senderId, receiverId]..sort();
        final chatRoomId = ids.join('_');
        final msg = Message.fromNotification(data);

        // Save to Hive (UI listening to this box will update instantly)
        HiveService().addMessage(chatRoomId, msg);
      }
    } catch (e) {
      debugPrint('Error saving foreground message: $e');
    }

    // Show Notification
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    final String? senderId = message.data['senderID'];
    final String? receiverId = message.data['receiverID'];

    // Don't show/play if this notification is not for us
    if (receiverId != _auth.currentUser?.uid) return;

    // If we're in the chat with this sender, skip - chat provider handles the sound
    if (senderId == _currentChatUserId) {
      return;
    }

    // Otherwise play notification sound and show notification
    SoundService().playNotification();

    // Show notification - use data payload as fallback if notification payload missing
    final title =
        notification?.title ?? message.data['senderName'] ?? 'New Message';
    final body =
        notification?.body ??
        message.data['message'] ??
        'You have a new message';

    _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          icon: '@mipmap/ic_launcher',
          importance: Importance.max,
          priority: Priority.high,
          playSound: false, // Disable system sound, we play our own
        ),
        iOS: DarwinNotificationDetails(
          presentSound: false, // Disable iOS system sound too
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleMessageTap(RemoteMessage message) {
    _navigateFromData(message.data);
  }

  void _navigateFromData(Map<String, dynamic> data) {
    final String? senderName = data['senderName'];
    final String? senderId = data['senderID']; // Ensure case matches payload
    final String? photoUrl = data['photoUrl'];

    if (senderId != null) {
      // Use the global navigator key
      final context = navigatorKey.currentContext;
      if (context != null) {
        // GoRouter push
        context.push('/chat/$senderName/$senderId', extra: photoUrl);
      } else {
        debugPrint('⚠️ Navigator Context is NULL. Cannot navigate.');
      }
    }
  }

  Future<void> _setupForegroundNotifications() async {
    // Android Channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    // Initialization
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null) {
          try {
            final data = jsonDecode(details.payload!);
            _navigateFromData(data);
          } catch (e) {
            debugPrint('Payload parse error: $e');
          }
        }
      },
    );
  }

  Future<void> _requestPermission() async {
    await _firebaseMessaging.requestPermission();
  }

  Future<void> _getToken() async {
    if (kIsWeb) return;
    String? token = await _firebaseMessaging.getToken();
    if (token != null) _saveTokenToFirestore(token);
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _fireStore.collection('Users').doc(user.uid).set({
        'token': token,
      }, SetOptions(merge: true));
    }
  }
}
