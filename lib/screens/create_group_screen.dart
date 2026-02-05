import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:social/services/chat_service.dart';
import 'package:social/services/storage_service.dart';

class CreateGroupScreen extends StatefulWidget {
  /// Pre-selected users from the new chat sheet
  final List<Map<String, dynamic>> selectedUsers;

  const CreateGroupScreen({super.key, this.selectedUsers = const []});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _groupNameController = TextEditingController();
  final _chatService = ChatService();
  final _storageService = StorageService();
  final _imagePicker = ImagePicker();

  File? _groupPhoto;
  bool _isLoading = false;

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _pickGroupPhoto() async {
    final pickedFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (pickedFile != null) {
      setState(() {
        _groupPhoto = File(pickedFile.path);
      });
    }
  }

  Future<void> _createGroup() async {
    final groupName = _groupNameController.text.trim();

    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }

    if (widget.selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one member')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Upload group photo if selected
      String? groupPhotoUrl;
      if (_groupPhoto != null) {
        final bytes = await _groupPhoto!.readAsBytes();
        groupPhotoUrl = await _storageService.uploadGroupPhoto(
          'group_${DateTime.now().millisecondsSinceEpoch}.jpg',
          bytes,
        );
      }

      // Get selected user IDs
      final userIds = widget.selectedUsers
          .map((user) => user['uid'] as String)
          .toList();

      // Create the group
      await _chatService.createGroup(
        groupName,
        userIds,
        groupPhotoUrl: groupPhotoUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group created successfully!')),
        );
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating group: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Group'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // GROUP PHOTO
            GestureDetector(
              onTap: _pickGroupPhoto,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    backgroundImage: _groupPhoto != null
                        ? FileImage(_groupPhoto!)
                        : null,
                    child: _groupPhoto == null
                        ? Icon(
                            Icons.group,
                            size: 50,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSecondaryContainer,
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Icon(
                        Icons.camera_alt,
                        size: 18,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // GROUP NAME
            TextField(
              controller: _groupNameController,
              decoration: InputDecoration(
                labelText: 'Group Name',
                hintText: 'Enter group name',
                prefixIcon: const Icon(Icons.group),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 24),

            // SELECTED MEMBERS SECTION
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Members (${widget.selectedUsers.length})',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),

            // MEMBER CHIPS
            if (widget.selectedUsers.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.selectedUsers.map((user) {
                  return Chip(
                    avatar: CircleAvatar(
                      backgroundImage:
                          user['profileImage'] != null &&
                              user['profileImage'].isNotEmpty
                          ? CachedNetworkImageProvider(user['profileImage'])
                          : null,
                      child:
                          user['profileImage'] == null ||
                              user['profileImage'].isEmpty
                          ? const Icon(Icons.person, size: 16)
                          : null,
                    ),
                    label: Text(user['username'] ?? 'Unknown'),
                  );
                }).toList(),
              )
            else
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'No members selected.\nGo back and select users to add.',
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 32),

            // CREATE BUTTON
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _isLoading ? null : _createGroup,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Create Group',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
