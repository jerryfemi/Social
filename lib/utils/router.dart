import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social/providers/auth_provider.dart';
import 'package:social/screens/create_group_screen.dart';
import 'package:social/screens/edit_video_screen.dart';
import 'package:social/screens/blocked_user_screen.dart';
import 'package:social/screens/chat_media_screen.dart';
import 'package:social/screens/chat_profile_screen.dart';
import 'package:social/screens/chat_screen.dart';
import 'package:social/screens/group_info_screen.dart';
import 'package:social/screens/group_media_screen.dart';
import 'package:social/screens/home_screen.dart';
import 'package:social/screens/login_screen.dart';
import 'package:social/screens/profile_screen.dart';
import 'package:social/screens/register_screen.dart';
import 'package:social/screens/settings_screen.dart';
import 'package:social/screens/starred_messages_screen.dart';
import 'package:social/screens/video_player_screen.dart';
import 'package:social/screens/view_image_screen.dart';
import 'package:social/widgets/my_bottom_nav_bar.dart';

// Global navigator key for accessing navigation outside of Riverpod
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// This is the KEY: use StateProvider to hold the router reference
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/login',
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/login'),
      // LOGIN
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),

      // PROFILE SCREEN
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),

      // STARRED MESSAGES SCREEN
      GoRoute(
        path: '/starred/:uid',
        builder: (context, state) {
          final chatRoomId = state.extra as String?;
          final uid = state.pathParameters['uid']!;
          return StarredMessagesScreen(chatRoomId: chatRoomId, receiverId: uid);
        },
      ),

      // BLOCKED USERS SCREEN
      GoRoute(
        path: '/blocked',
        builder: (context, state) => const BlockedUserScreen(),
      ),

      // CREATE GROUP SCREEN
      GoRoute(
        path: '/create-group',
        builder: (context, state) {
          final selectedUsers =
              state.extra as List<Map<String, dynamic>>? ?? [];
          return CreateGroupScreen(selectedUsers: selectedUsers);
        },
      ),

      //REGISTER UP SCREEN
      GoRoute(
        path: '/signup',
        builder: (context, state) => const RegisterScreen(),
      ),

      // CHAT SCREEN
      GoRoute(
        path: '/chat/:receiverName/:receiverID',
        builder: (context, state) {
          final receiverName = state.pathParameters['receiverName']!;
          final receiverId = state.pathParameters['receiverID']!;

          // Extra can be a String (photoUrl) or Map with photoUrl, scrollToMessageId, isGroup
          String? photoUrl;
          String? scrollToMessageId;
          bool isGroup = false;

          if (state.extra is String?) {
            photoUrl = state.extra as String?;
          } else if (state.extra is Map<String, dynamic>) {
            final extraMap = state.extra as Map<String, dynamic>;
            photoUrl = extraMap['photoUrl'] as String?;
            scrollToMessageId = extraMap['scrollToMessageId'] as String?;
            isGroup = extraMap['isGroup'] as bool? ?? false;
          }

          return ChatScreen(
            photoUrl: photoUrl,
            receiverName: receiverName,
            receiverId: receiverId,
            scrollToMessageId: scrollToMessageId,
            isGroup: isGroup,
          );
        },
      ),

      // CHAT PROFILE SCREEN
      GoRoute(
        path: '/chat_profile/:uid',
        builder: (context, state) {
          final uid = state.pathParameters['uid']!;
          return ChatProfileScreen(receiverId: uid);
        },
      ),

      // CHAT MEDIA SCREEN
      GoRoute(
        path: '/chat_media/:uid',
        builder: (context, state) {
          final uid = state.pathParameters['uid']!;
          return ChatMediaScreen(receiverId: uid);
        },
      ),

      // GROUP INFO SCREEN
      GoRoute(
        path: '/group_info/:groupId',
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          final photoUrl = state.extra as String?;
          return GroupInfoScreen(groupId: groupId, photoUrl: photoUrl);
        },
      ),

      // GROUP MEDIA SCREEN
      GoRoute(
        path: '/group_media/:groupId',
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return GroupMediaScreen(groupId: groupId);
        },
      ),

      // EDIT VIDEO SCREEN
      GoRoute(
        path: '/editVideo',
        builder: (context, state) {
          final path = state.extra as String;
          return EditVideoScreen(file: File(path));
        },
      ),

      // VIDEO PLAYER SCREEN
      GoRoute(
        path: '/videoPlayer',
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>;
          return VideoPlayerScreen(
            videoUrl: data['videoUrl'],
            caption: data['caption'],
          );
        },
      ),
      GoRoute(
        path: '/viewImage',
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>;
          return ViewImageScreen(
            imageUrl: data['photoUrl'],
            caption: data['caption'],
            isProfile: data['isProfile'] ?? false,
            senderName: data['senderName'],
            timestamp: data['timestamp'],
          );
        },
      ),

      // SHELL ROUTE
      ShellRoute(
        builder: (context, state, child) => Scaffold(
          extendBody: true,
          bottomNavigationBar: const MyBottomNavBar(),
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: child,
        ),
        routes: [
          GoRoute(path: '/home', builder: (context, state) => HomeScreen()),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      // Get the auth service to check current user
      final authService = ref.read(authServiceProvider);
      final isLoggedIn = authService.currentUser != null;

      final currentPath = state.matchedLocation;
      final onLogin = currentPath == '/login';
      final onSignUp = currentPath == '/signup';

      // If not logged in and not on auth pages, redirect to login
      if (!isLoggedIn && !onLogin && !onSignUp) {
        return '/login';
      }

      // If logged in and on auth pages, redirect to home
      if (isLoggedIn && (onLogin || onSignUp)) {
        return '/home';
      }

      // Redirect root to login
      if (currentPath == '/') {
        return '/login';
      }

      return null;
    },
    refreshListenable: GoRouterRefreshStream(
      ref.read(authServiceProvider).authStateChanges,
    ),
  );

  // Listen to auth state changes and refresh router
  ref.listen<AsyncValue>(authStateProvider, (previous, next) {
    router.refresh();
  });

  return router;
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
