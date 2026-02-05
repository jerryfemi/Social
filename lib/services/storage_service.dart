import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  // DELETE CHAT WALLPAPER FILE
  Future<void> deleteChatWallpaperFile(String? wallpaperUrl) async {
    if (wallpaperUrl == null || wallpaperUrl.isEmpty) return;
    try {
      final ref = _storage.refFromURL(wallpaperUrl);
      await ref.delete();
      print('Deleted chat wallpaper from storage.');
    } catch (e) {
      print('Error deleting chat wallpaper: $e');
    }
  }

  final FirebaseStorage _storage = FirebaseStorage.instance;

  //  UPLOAD PROFILE PHOTO
  Future<String> uploadProfilePhoto(
    String userId,
    Uint8List? fileBytes,
    String fileName,
  ) async {
    try {
      // Reference: profile_images/userId/filename
      final ref = _storage.ref().child('profile_images/$userId/$fileName');

      // determin content type
      String contentType = 'image.jpeg';
      if (fileName.endsWith('png')) contentType = 'image.png';

      // Upload
      UploadTask uploadTask = ref.putData(
        fileBytes!,
        SettableMetadata(contentType: contentType),
      );

      print('uploadingg');
      // Wait for completion
      TaskSnapshot snapshot = await uploadTask;
      print('downlaodin');
      // Get URL
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      throw 'Failed to upload photo: $e';
    }
  }

  // DELETE PROFILE PHOTO
  Future<void> deleteProfilePhoto(String? photoUrl) async {
    if (photoUrl == null || photoUrl.isEmpty) return;

    try {
      final ref = _storage.refFromURL(photoUrl);
      await ref.delete();
      print('deleted image......');
    } catch (e) {
      print('Error deleting old image: $e');
    }
  }

  // UPDATE PROFILE PHOTO (Delete Old + Upload New)
  Future<String> updateProfilePhoto(
    String userId,
    Uint8List? newFile,
    String? oldUrl,
    String fileName,
  ) async {
    // Attempt to delete the old one first
    if (oldUrl != null && oldUrl.isNotEmpty) {
      await deleteProfilePhoto(oldUrl);
    }

    // Upload the new one
    return await uploadProfilePhoto(userId, newFile, fileName);
  }

  // UPLOAD CHAT FILE
  Future<String> uploadChatFile(
    String chatRoomId,
    String fileName, {
    Uint8List? filebytes,
    File? file,
  }) async {
    try {
      // Create reference: chat_media/chatRoomID/filename
      final ref = _storage.ref().child('chat_media/$chatRoomId/$fileName');

      // upload
      UploadTask uploadTask;
      if (file != null) {
        uploadTask = ref.putFile(
          file,
          SettableMetadata(contentType: 'video/mp4'),
        );
      } else if (filebytes != null) {
        // Determine content type
        String contentType = 'image/jpeg';
        if (fileName.endsWith('.png')) contentType = 'image/png';

        uploadTask = ref.putData(
          filebytes,
          SettableMetadata(contentType: contentType),
        );
      } else {
        throw 'No file provided';
      }

      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      throw 'Failed to upload chat media: $e';
    }
  }

  // UPLOAD GROUP PHOTO
  Future<String> uploadGroupPhoto(String fileName, Uint8List fileBytes) async {
    try {
      // Reference: group_images/filename
      final ref = _storage.ref().child('group_images/$fileName');

      // Determine content type
      String contentType = 'image/jpeg';
      if (fileName.endsWith('.png')) contentType = 'image/png';

      UploadTask uploadTask = ref.putData(
        fileBytes,
        SettableMetadata(contentType: contentType),
      );

      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      throw 'Failed to upload group photo: $e';
    }
  }
}
