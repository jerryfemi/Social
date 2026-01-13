import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:social/utils/router.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _fireStore = FirebaseFirestore.instance;

  // Local notifications for foreground
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final AndroidNotificationChannel _channel = const AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.max,
  );

  // initialize
  Future<void> initNotifications() async {
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
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              icon: '@mipmap/ic_launcher',
            ),
          ),
          payload: jsonEncode(message.data),
        );
      }
    });

    // Handle tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNavigation);

    // Handle tap when app is terminated
    RemoteMessage? initialMessage = await _firebaseMessaging
        .getInitialMessage();
    if (initialMessage != null) {
      // little delay
      Future.delayed(
        const Duration(milliseconds: 500),
        () => _handleNavigation(initialMessage),
      );
    }
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
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null) {
          _handleNavigationFromPayload(details.payload!);
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

  void _handleNavigationFromPayload(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final String? senderName = data['senderName'];
      final String? senderId = data['senderID'];
      final String? photoUrl = data['photoUrl'];

      if (senderId != null && senderName != null) {
        navigatorKey.currentContext?.go(
          '/chat/$senderName/$senderId',
          extra: photoUrl,
        );
      }
    } catch (e) {
      print('Error parsing notification payload: $e');
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
      print('USER AUTHORIZED');
    } else if (settings.authorizationStatus ==
        AuthorizationStatus.provisional) {
      print('user granted provisional permission');
    } else {
      print('PERMISSION DENIED');
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
          print('Notifications not authorized on web');
          return;
        }
      }

      String? token = await _firebaseMessaging.getToken();

      if (token != null) {
        print('FCM token: $token');
        await _saveTokenToFirestore(token);
      }
    } catch (e) {
      print('error getting token: $e');
      // On web, service worker issues shouldn't crash the app
      if (!kIsWeb) {
        rethrow;
      }
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

  void _handleNavigation(RemoteMessage message) {
    final String? senderName = message.data['senderName'];
    final String? senderId = message.data['senderID'];
    final String? photoUrl = message.data['photoUrl'];

    if (senderId != null && senderName != null) {
      // Use the global navigator key to navigate
      navigatorKey.currentContext?.go(
        '/chat/$senderName/$senderId',
        extra: photoUrl,
      );
    }
  }
}
