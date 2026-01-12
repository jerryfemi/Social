import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social/providers/auth_provider.dart';
import 'package:social/providers/chat_provider.dart';
import 'package:social/widgets/my_alert_dialog.dart';
import 'package:social/widgets/user_tile.dart';

class BlockedUserScreen extends ConsumerWidget {
  const BlockedUserScreen({super.key});

  void showUnblockDialog(
    BuildContext context,
    WidgetRef ref,
    String blockedUserId,
  ) {
    showDialog(
      context: context,
      builder: (context) => MyAlertDialog(
        content: 'Are you sure you want to unblock this user?',
        title: ' Unblock',
        text: 'unblock',
        onpressed: () {
          ref.read(chatServiceProvider).unblockUser(blockedUserId);
          context.pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authServiceProvider).currentUser!.uid;
    final blockedUsersStream = ref.watch(blockedUsersProvider(userId));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Blocked',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: blockedUsersStream.when(
        error: (error, stackTrace) => const Center(child: Text('Error')),
        loading: () => Center(child: CircularProgressIndicator()),
        data: (blockedUsers) {
          // empty state
          if (blockedUsers.isEmpty) {
            return const Center(child: Text('No blocked Users'));
          }
          return ListView.builder(
            itemCount: blockedUsers.length,
            itemBuilder: (context, index) {
              final users = blockedUsers[index];

              return Padding(
                padding: const EdgeInsets.all(25.0),
                child: UserTile(
                  onTap: () => showUnblockDialog(context, ref, users['uid']),
                  text: users['email'],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
