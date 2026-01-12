import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _fireStore = FirebaseFirestore.instance;

  // initialize
  Future<void> initNotifications() async {
    // request permission
    await _requestPermission();

    // get token
    await _getToken();

    // listen for token refrences
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      _saveTokenToFirestore(newToken);
    });
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
}
