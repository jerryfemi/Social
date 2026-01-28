import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:social/widgets/my_button.dart';

class GifPreviewDialog extends StatefulWidget {
  final String gifUrl;
  const GifPreviewDialog({super.key, required this.gifUrl});

  @override
  State<GifPreviewDialog> createState() => _GifPreviewDialogState();
}

class _GifPreviewDialogState extends State<GifPreviewDialog> {
  final _captionController = TextEditingController();

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(20),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Send GIF',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close),
                ),
              ],
            ),
            SizedBox(height: 10),

            // GIF Preview
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: widget.gifUrl,
                placeholder: (context, url) => Container(
                  height: 200,
                  color: Colors.grey[200],
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 200,
                  color: Colors.grey[200],
                  child: Icon(Icons.error),
                ),
                fit: BoxFit.contain,
              ),
            ),
            SizedBox(height: 16),

            // Caption Field
            TextField(
              controller: _captionController,
              decoration: InputDecoration(
                hintText: 'Add a caption...',
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            SizedBox(height: 16),

            // Send Button
            SizedBox(
              width: double.infinity,
              child: MyButton(
                onTap: () {
                  Navigator.pop(context, _captionController.text.trim());
                },
                child: Text(
                  'Send',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
