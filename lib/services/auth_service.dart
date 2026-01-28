import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:social/services/hive_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Sign in with Email and Password
  Future<UserCredential?> signinWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      return userCredential;
    } on PlatformException catch (e) {
      throw _handlePlatformError(e);
    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseAuthError(e);
    }
  }

  // Sign up with Email and Password
  Future<UserCredential?> signUpWIthEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // default username
      String defaultUsername = email.split('@')[0];

      // save user info
      _firestore.collection('Users').doc(userCredential.user!.uid).set({
        'uid': userCredential.user!.uid,
        'email': email,
        'username': defaultUsername,
        'about': " Hey there, Lets's connect.",
        'profileImage': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
        'searchKey': defaultUsername.toLowerCase(),
      });
      return userCredential;
    } on PlatformException catch (e) {
      throw _handlePlatformError(e);
    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseAuthError(e);
    }
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // sign in to firebase withcredential
      UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      final userDoc = await _firestore
          .collection('Users')
          .doc(userCredential.user!.uid)
          .get();

      // check is user exists in firestore if not create doc
      if (!userDoc.exists) {
        String name = userCredential.user!.displayName ?? 'User';
        _firestore.collection('Users').doc(userCredential.user!.uid).set({
          'uid': userCredential.user!.uid,
          'email': userCredential.user!.email,
          'username': name,
          'about': " Hey there, Lets's connect.",
          'profileImage': userCredential.user!.photoURL ?? '',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'searchKey': name.toLowerCase(),
        });
      }
      return userCredential;
    } catch (e) {
      throw 'Google Sign-In failed: $e';
    }
  }

  // reset password
  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // sign out
  Future<void> signOut() async {
    try {
      // 1. Remove FCM Token to stop notifications for this user on this device
      final user = _auth.currentUser;
      if (user != null) {
        // Option A: Just delete the "token" field
        await _firestore.collection('Users').doc(user.uid).update({
          'token': FieldValue.delete(),
        });
      }
    } catch (e) {
      // Ignore token delete errors (e.g. permission issues or offline)
    }

    await HiveService().clearOnLogout();
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}

String _handlePlatformError(PlatformException e) {
  if (e.code == 'network_error' || e.message?.contains('network') == true) {
    return 'No internet connection. Please check your network and try again.';
  }
  return 'Sign in failed. Please try again.';
}

String _handleFirebaseAuthError(FirebaseAuthException e) {
  switch (e.code) {
    case 'user-not-found':
      return 'No account found for this email.';
    case 'wrong-password':
    case 'invalid-credential': // ADD THIS LINE
      return 'Incorrect password or email.';
    case 'email-already-in-use':
      return 'That email is already registered.';
    case 'weak-password':
      return 'Password is too weak.';
    case 'invalid-email':
      return 'Invalid email address.';
    case 'too-many-requests':
      return 'Too many attempts. Please try again later.';
    default:
      return e.message ?? 'Authentication failed. Please try again.';
  }
}
