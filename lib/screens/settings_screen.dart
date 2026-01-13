import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social/providers/auth_provider.dart';
import 'package:social/providers/chat_provider.dart';
import 'package:social/providers/theme_provider.dart';
import 'package:social/widgets/my_alert_dialog.dart';
import 'package:social/widgets/user_tile.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // sign out
  void _signOut() {
    showDialog(
      context: context,
      builder: (context) => MyAlertDialog(
        content: 'Are you sure you want to sign out?',
        title: 'Sign out',
        text: 'sign out',
        onpressed: () => ref.read(authServiceProvider).signOut(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authServiceProvider).currentUser;
    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }
    final userProfileAsync = ref.watch(userProfileProvider(currentUser.uid));
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        // backgroundColor: Colors.transparent,
        title: const Text(
          'Settings',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),
      body: userProfileAsync.when(
        error: (error, stackTrace) =>
            Center(child: Text('Error :${error.toString()}')),
        loading: () => Center(child: CircularProgressIndicator()),
        data: (profile) {
          final userData = profile.data() as Map<String, dynamic>?;

          if (userData == null) {
            return const Center(child: Text('No data Found'));
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
            child: Column(
              children: [
                profileView(context, userData),

                SizedBox(height: 50),

                MyTile(
                  title: 'Starred',
                  leading: Icon(Icons.star_outline),
                  ontap: () => context.push('/starred/${userData['uid']}'),
                ),
                MyTile(
                  title: 'Blocked',
                  leading: Icon(Icons.logout),
                  ontap: () => context.push('/blocked'),
                ),
                MyTile(
                  title: 'Dark Mode',
                  leading: Icon(
                    themeMode == ThemeMode.dark
                        ? Icons.dark_mode
                        : Icons.light_mode,
                  ),
                  trailing: Switch(
                    value: themeMode == ThemeMode.dark,
                    onChanged: (_) =>
                        ref.read(themeModeProvider.notifier).toggle(),
                  ),
                ),
                Spacer(),
                MyTile(
                  title: 'Logout',
                  leading: Icon(Icons.logout),
                  ontap: _signOut,
                ),
                SizedBox(height: 10),
              ],
            ),
          );
        },
      ),
    );
  }
}

// profile view
Widget profileView(BuildContext context, Map<String, dynamic> userData) {
  return InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () => context.push('/profile'),
    child: Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // profile photo
          ClipOval(
            child:
                userData['profileImage'] != null &&
                    userData['profileImage'].isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: userData['profileImage'],
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        const CircularProgressIndicator(),
                    errorWidget: (context, url, error) => Icon(
                      Icons.person,
                      size: 50,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  )
                : CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    radius: 40,
                    child: Icon(
                      Icons.person,
                      size: 40,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
          ),
          SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // user name
              Text(
                userData['username'] ?? 'Unknown',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              // user email
              Text(userData['email'] ?? ''),
            ],
          ),
        ],
      ),
    ),
  );
}
