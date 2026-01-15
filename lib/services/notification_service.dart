import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:social/utils/router.dart';

class NotificationService {
  // Singleton pattern
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _fireStore = FirebaseFirestore.instance;

  // Track current chat to suppress notifications
  String? _currentChatUserId;

  // Store pending navigation data for when app opens from terminated state
  Map<String, dynamic>? _pendingNotificationData;
  bool _isInitialized = false;

  // Track message counts per sender for grouping
  final Map<String, int> _messageCountPerSender = {};
  final Map<String, List<String>> _messagesPerSender = {};

  // Group key for bundled notifications
  static const String _groupKey = 'com.example.social.MESSAGES';

  // Local notifications for foreground only
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final AndroidNotificationChannel _channel = const AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.max,
  );

  /// Call this when entering a chat screen
  void setCurrentChat(String? userId) {
    _currentChatUserId = userId;
    debugPrint('NotificationService: Current chat set to $userId');
  }

  /// Call this when leaving a chat screen
  void clearCurrentChat() {
    _currentChatUserId = null;
    debugPrint('NotificationService: Current chat cleared');
  }

  /// Clear all notifications from the tray (call when app opens/resumes)
  Future<void> clearAllNotifications() async {
    await _localNotifications.cancelAll();
    _messageCountPerSender.clear();
    _messagesPerSender.clear();
    debugPrint('NotificationService: All notifications cleared');
  }

  // initialize - call this early in main.dart
  Future<void> initNotifications() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // request permission
    await _requestPermission();

    // get token
    await _getToken();

    // Setup foreground notifications
    await _setupForegroundNotifications();

    // listen for token refrences
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      _saveTokenToFirestore(newToken);
    });

    // Listen for foreground messages and show local notification
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle tap when app is in background (not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    // Handle tap when app was terminated - store for later processing
    RemoteMessage? initialMessage = await _firebaseMessaging
        .getInitialMessage();
    if (initialMessage != null) {
      debugPrint('App opened from terminated state with notification');
      _pendingNotificationData = initialMessage.data;
    }
  }

  /// Call this after the router is ready (e.g., in home screen initState)
  void processPendingNotification() {
    if (_pendingNotificationData != null) {
      debugPrint('Processing pending notification navigation');
      final data = _pendingNotificationData!;
      _pendingNotificationData = null;
      // Small delay to ensure navigation context is fully ready
      Future.delayed(const Duration(milliseconds: 300), () {
        _navigateFromData(data);
      });
    }
  }

  /// Handle foreground messages - show grouped local notification
  void _handleForegroundMessage(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification == null || android == null) return;

    // Get sender info from the message data
    final String? senderId = message.data['senderID'];
    final String? senderName = notification.title;
    final String? messageBody = notification.body;

    // Debug logging
    debugPrint('=== NOTIFICATION DEBUG ===');
    debugPrint('Received notification from senderId: $senderId');
    debugPrint('Current chat userId: $_currentChatUserId');
    debugPrint('Are they equal? ${senderId == _currentChatUserId}');
    debugPrint('Full message.data: ${message.data}');
    debugPrint('==========================');

    // Don't show notification if we're already in that chat
    if (senderId != null && senderId == _currentChatUserId) {
      debugPrint('Suppressing notification - already in chat with $senderId');
      return;
    }

    if (senderId == null || senderName == null) return;

    // Track messages per sender
    _messageCountPerSender[senderId] =
        (_messageCountPerSender[senderId] ?? 0) + 1;
    _messagesPerSender[senderId] ??= [];
    if (messageBody != null) {
      _messagesPerSender[senderId]!.add(messageBody);
      // Keep only last 5 messages for inbox style
      if (_messagesPerSender[senderId]!.length > 5) {
        _messagesPerSender[senderId]!.removeAt(0);
      }
    }

    final int messageCount = _messageCountPerSender[senderId]!;
    final List<String> messages = _messagesPerSender[senderId]!;

    // Create notification ID based on sender (so same sender updates the same notification)
    final int notificationId = senderId.hashCode;

    // Build inbox style for multiple messages
    final InboxStyleInformation? inboxStyle = messageCount > 1
        ? InboxStyleInformation(
            messages,
            contentTitle: '$messageCount messages from $senderName',
            summaryText: '$messageCount messages',
          )
        : null;

    // Show individual notification (grouped)
    _localNotifications.show(
      notificationId,
      messageCount > 1 ? '$senderName ($messageCount)' : senderName,
      messageCount > 1 ? '${messages.last}' : messageBody,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          icon: '@mipmap/ic_launcher',
          importance: Importance.max,
          priority: Priority.high,
          groupKey: _groupKey,
          styleInformation: inboxStyle,
          setAsGroupSummary: false,
        ),
        iOS: DarwinNotificationDetails(threadIdentifier: senderId),
      ),
      payload: jsonEncode(message.data),
    );

    // Show/update summary notification (for grouping multiple senders)
    _showGroupSummary();
  }

  /// Show summary notification for grouped messages
  Future<void> _showGroupSummary() async {
    final int totalSenders = _messageCountPerSender.keys.length;
    if (totalSenders <= 1) return; // No need for summary with single sender

    final int totalMessages = _messageCountPerSender.values.fold(
      0,
      (a, b) => a + b,
    );

    await _localNotifications.show(
      0, // Summary notification ID
      'Social',
      '$totalMessages messages from $totalSenders chats',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          icon: '@mipmap/ic_launcher',
          groupKey: _groupKey,
          setAsGroupSummary: true,
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }

  Future<void> _setupForegroundNotifications() async {
    // Create the channel on Android
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    // Initialize settings for Android and iOS
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        debugPrint('Local notification tapped: ${details.payload}');
        if (details.payload != null) {
          _navigateToChat(details.payload!);
        }
      },
    );

    // iOS foreground presentation options
    await _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  /// Navigate to chat from notification payload (JSON string)
  void _navigateToChat(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      _navigateFromData(data);
    } catch (e) {
      debugPrint('Error parsing notification payload: $e');
    }
  }

  /// Handle tap on FCM notification (background/terminated)
  void _handleMessageTap(RemoteMessage message) {
    debugPrint('Notification tapped: ${message.data}');
    _navigateFromData(message.data);
  }

  /// Navigate to chat screen from notification data
  void _navigateFromData(Map<String, dynamic> data, {int retryCount = 0}) {
    final String? senderName = data['senderName'];
    final String? senderId = data['senderID'];
    final String? photoUrl = data['photoUrl'];

    debugPrint('Navigating to chat: $senderName ($senderId)');

    if (senderId == null || senderName == null) {
      debugPrint('Missing senderId or senderName in notification data');
      return;
    }

    // Use the router to navigate with GoRouter
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      try {
        context.push('/chat/$senderName/$senderId', extra: photoUrl);
      } catch (e) {
        debugPrint('Navigation error: $e');
        if (retryCount < 5) {
          Future.delayed(const Duration(milliseconds: 500), () {
            _navigateFromData(data, retryCount: retryCount + 1);
          });
        }
      }
    } else if (retryCount < 10) {
      debugPrint(
        'Navigator context is null - retrying in 500ms (attempt ${retryCount + 1})',
      );
      // Retry after a short delay if context isn't ready
      Future.delayed(const Duration(milliseconds: 500), () {
        _navigateFromData(data, retryCount: retryCount + 1);
      });
    } else {
      debugPrint('Failed to navigate after $retryCount retries');
    }
  }

  // request permission
  Future<void> _requestPermission() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('Notification permission: AUTHORIZED');
    } else if (settings.authorizationStatus ==
        AuthorizationStatus.provisional) {
      debugPrint('Notification permission: PROVISIONAL');
    } else {
      debugPrint('Notification permission: DENIED');
    }
  }

  // get token
  Future<void> _getToken() async {
    try {
      // On web, we need to skip if service worker registration fails
      if (kIsWeb) {
        // Check if notifications are supported
        final settings = await _firebaseMessaging.getNotificationSettings();
        if (settings.authorizationStatus != AuthorizationStatus.authorized) {
          debugPrint('Notifications not authorized on web');
          return;
        }
      }

      String? token = await _firebaseMessaging.getToken();

      if (token != null) {
        debugPrint('FCM token obtained');
        await _saveTokenToFirestore(token);
      }
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      // Don't rethrow - FCM token failure shouldn't crash the app
      // Notifications just won't work until service is available
    }
  }

  //save token
  Future<void> _saveTokenToFirestore(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // save token to user's document
    await _fireStore.collection('Users').doc(user.uid).set({
      'token': token,
    }, SetOptions(merge: true));
  }
}
