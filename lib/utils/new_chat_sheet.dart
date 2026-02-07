import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social/providers/chat_provider.dart';
import 'package:social/services/auth_service.dart';
import 'package:social/widgets/user_tile.dart';

class NewChatSheet extends ConsumerStatefulWidget {
  final Set<String> selectedUserIds;
  final List<Map<String, dynamic>> preSelectedUsers;
  const NewChatSheet({
    super.key,
    this.selectedUserIds = const {},
    this.preSelectedUsers = const [],
  });
  @override
  ConsumerState<NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<NewChatSheet> {
  final authService = AuthService();
  String _searchQuery = '';
  final TextEditingController controller = TextEditingController();

  // Selection mode state
  bool _isSelectionMode = false;
  Set<String> _selectedUserIds = {};
  // Store selected user data for passing to create group screen
  final List<Map<String, dynamic>> _selectedUsers = [];

  @override
  void initState() {
    super.initState();
    // If pre-selected users exist, enter selection mode
    if (widget.selectedUserIds.isNotEmpty) {
      _isSelectionMode = true;
      _selectedUserIds = Set.from(widget.selectedUserIds);
      _selectedUsers.addAll(widget.preSelectedUsers);
    }
  }

  void _enterSelectionMode(Map<String, dynamic> userData) {
    setState(() {
      _isSelectionMode = true;
      _selectedUserIds.add(userData['uid']);
      _selectedUsers.add(userData);
    });
  }

  void _toggleSelection(Map<String, dynamic> userData) {
    final userId = userData['uid'];
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
        _selectedUsers.removeWhere((u) => u['uid'] == userId);

        // Exit selection mode if no users selected
        if (_selectedUserIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedUserIds.add(userId);
        _selectedUsers.add(userData);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedUserIds.clear();
      _selectedUsers.clear();
    });
  }

  void _goToCreateGroup() {
    context.pop(context);
    context.push('/create-group', extra: _selectedUsers);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
        child: Column(
          children: [
            // HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // X button (only in selection mode)
                if (_isSelectionMode)
                  IconButton(
                    onPressed: _exitSelectionMode,
                    icon: Icon(Icons.close),
                  )
                else
                  const SizedBox(width: 48), // Placeholder for alignment
                // Title
                Text(
                  _isSelectionMode
                      ? '${_selectedUserIds.length} selected'
                      : 'New Chat',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                // Placeholder for alignment
                const SizedBox(width: 48),
              ],
            ),
            SizedBox(height: 20),

            // SEARCH BAR
            Container(
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoSearchTextField(
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                controller: controller,
                placeholder: 'Search users...',
                placeholderStyle: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            SizedBox(height: 10),

            // Create New Group tile (only in normal mode)
            if (!_isSelectionMode)
              MyTile(
                title: 'Create New Group',
                leading: Icon(Icons.group_add),
                ontap: () => context.push('/create-group'),
              ),

            // Add to Group button (only in selection mode)
            if (_isSelectionMode)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _selectedUserIds.isNotEmpty
                        ? _goToCreateGroup
                        : null,
                    icon: Icon(Icons.group_add),
                    label: Text('Add to Group (${_selectedUserIds.length})'),
                  ),
                ),
              ),

            // USER LIST
            Expanded(
              child: Builder(
                builder: (context) {
                  final userList =
                      ref.watch(searchUsersProvider(_searchQuery)).value ?? [];
                  if (userList.isEmpty) {
                    return _buildEmptyContent(context);
                  }
                  return _buildContent(context, userList);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<Map<String, dynamic>> users) {
    // When pre-selected from home screen, we need to populate _selectedUsers
    // with the actual user data when we see them in the list
    if (widget.selectedUserIds.isNotEmpty && _selectedUsers.isEmpty) {
      for (final userData in users) {
        if (_selectedUserIds.contains(userData['uid']) &&
            !_selectedUsers.any((u) => u['uid'] == userData['uid'])) {
          _selectedUsers.add(userData);
        }
      }
    }

    return ListView.builder(
      itemBuilder: (context, index) {
        final userData = users[index];
        final isSelected = _selectedUserIds.contains(userData['uid']);

        return UserTile(
          onTap: () {
            if (_isSelectionMode) {
              _toggleSelection(userData);
            } else {
              context.pop(context);
              context.push(
                '/chat/${userData['username']}/${userData['uid']}',
                extra: userData['profileImage'],
              );
            }
          },
          onLongPress: () {
            if (!_isSelectionMode) {
              _enterSelectionMode(userData);
            }
          },
          text: userData['username'],
          photourl: userData['profileImage'],
          trailing: isSelected
              ? Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                )
              : null,
        );
      },
      itemCount: users.length,
    );
  }

  Widget _buildEmptyContent(BuildContext context) {
    bool isSearching = _searchQuery.isNotEmpty;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearching
                ? Icons.search_off_rounded
                : Icons.chat_bubble_outline_rounded,
            size: 60,
            color: Theme.of(context).colorScheme.secondary,
          ),
          Text(
            isSearching
                ? ' No users found named "$_searchQuery" '
                : 'Search above to start chatting!',
          ),
        ],
      ),
    );
  }
}
