import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:social/providers/auth_provider.dart';
import 'package:social/providers/chat_provider.dart';
import 'package:social/providers/storage_service_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final nameController = TextEditingController();
  final aboutController = TextEditingController();
  final emailController = TextEditingController();
  final imagePicker = ImagePicker();

  String? _currentPhotoUrl;

  bool isUploadingImage = false;
  bool isSavingText = false;

  void _showSnackBar(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(title, style: TextStyle()),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    super.dispose();
    nameController.dispose();
    aboutController.dispose();
    emailController.dispose();
  }

  Future<void> _loadUserData() async {
    final chatService = ref.read(chatServiceProvider);
    final userDoc = await chatService.getCurrentUserData();

    if (userDoc.exists) {
      Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
      setState(() {
        nameController.text = data['username'] ?? '';
        aboutController.text = data['about'] ?? '';
        emailController.text = data['email'] ?? '';
        _currentPhotoUrl = data['profileImage'];
      });
    }
  }

  Future<void> pickAnUploadImage() async {
    final XFile? pickedFile = await imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (pickedFile == null) return;
    final bytes = await pickedFile.readAsBytes();
    setState(() => isUploadingImage = true);

    try {
      final storageService = ref.read(storageServiceProvider);
      final chatService = ref.read(chatServiceProvider);
      final authService = ref.read(authServiceProvider);

      final String uid = authService.currentUser!.uid;
      // upload new image and delete old
      final newUrl = await storageService.updateProfilePhoto(
        uid,
        bytes,
        _currentPhotoUrl,
        pickedFile.name,
      );

      await chatService.updateUserPhotoUrl(newUrl);

      setState(() {
        _currentPhotoUrl = newUrl;
      });
      _showSnackBar('Profile photo updated');
    } catch (e) {
      _showSnackBar('Failed to upload Profile photo:$e');
    } finally {
      if (mounted) setState(() => isUploadingImage = false);
    }
  }

  // save TextInput {About and Username}
  Future<void> _saveProfileInput() async {
    if (nameController.text.trim().isEmpty) return;
    setState(() => isSavingText = true);

    try {
      final chatService = ref.read(chatServiceProvider);
      await chatService.updateUserData(
        nameController.text,
        aboutController.text,
      );

      _showSnackBar('Updated');
    } catch (e) {
      _showSnackBar('Update failed: $e');
    } finally {
      setState(() => isSavingText = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Profile')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            children: [
              // circule avatar
              CircleAvatar(
                radius: 50,
                child: isUploadingImage
                    ? const CircularProgressIndicator()
                    : _currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty
                    ? GestureDetector(
                        onTap: () => context.push(
                          '/viewImage',
                          extra: {'photoUrl': _currentPhotoUrl, 'isProfile': true},
                        ),
                        child: ClipOval(
                          child: Hero(
                            tag: 'pfp',
                            child: CachedNetworkImage(
                              imageUrl: _currentPhotoUrl!,
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                              placeholder: (context, url) =>
                                  const Icon(Icons.person, size: 40),
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.person, size: 40),
                            ),
                          ),
                        ),
                      )
                    : const Icon(Icons.person, size: 40),
              ),

              SizedBox(height: 6),
              MaterialButton(onPressed: pickAnUploadImage, child: Text('Edit')),

              SizedBox(height: 50),

              TextField(
                decoration: InputDecoration(labelText: 'Name'),
                controller: nameController,
              ),
              SizedBox(height: 10),
              TextField(
                decoration: InputDecoration(labelText: 'About'),
                controller: aboutController,
              ),
              const SizedBox(height: 10),
              TextField(
                decoration: InputDecoration(labelText: 'Email'),
                controller: emailController,
                readOnly: true,
              ),
              const Spacer(),
              isSavingText
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _saveProfileInput,
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                      ),
                      child: Text('Save'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
