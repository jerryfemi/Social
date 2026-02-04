import 'package:flutter/material.dart';
import 'package:social/widgets/emoji_picker_widget.dart';
import 'package:social/widgets/giphy_picker_widget.dart';
import 'package:social/widgets/gif_preview_dialog.dart';

class AttachmentPickerSheet extends StatefulWidget {
  final TextEditingController mesageController;
  final Function(String url, String? caption) onSendGif;

  const AttachmentPickerSheet({
    super.key,
    required this.mesageController,
    required this.onSendGif,
  });

  @override
  State<AttachmentPickerSheet> createState() => _AttachmentPickerSheetState();
}

class _AttachmentPickerSheetState extends State<AttachmentPickerSheet> {
  // selected index
  int _selectedIndex = 0;
  final _searchController = TextEditingController();
  bool _isSearchVisible = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onGifLongPress(String url) async {
    // Show preview dialog
    final caption = await showDialog<String>(
      context: context,
      builder: (context) => GifPreviewDialog(gifUrl: url),
    );

    // If caption is not null (user sent), send it
    if (caption != null) {
      widget.onSendGif(url, caption);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboard = MediaQuery.of(context).viewInsets.bottom > 0;
    // When keyboard is open, show compact picker (about 1 row of emojis)
    final double pickerHeight = isKeyboard ? 100 : 355;
    // Account for the search bar/tabs row (~61px with padding)
    final double emojiHeight = isKeyboard ? 40 : 266;
    
    return SizedBox(
      height: pickerHeight,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Column(
          children: [
            // Search Bar & Tabs Row
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: _isSearchVisible
                  ? TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: _selectedIndex == 0
                            ? 'Search emojis...'
                            : 'Search GIFs...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              _isSearchVisible = false;
                              _searchController.clear();
                            });
                          },
                        ),
                      ),
                    )
                  : Container(
                      height: 45,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: BoxBorder.all(
                          color: Theme.of(context).colorScheme.secondary,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Search Button
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _isSearchVisible = true;
                              });
                            },
                            icon: Icon(
                              Icons.search,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),

                          // Tabs
                          Container(
                            decoration: BoxDecoration(
                              color: _selectedIndex == 0
                                  ? Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              onPressed: () {
                                setState(() {
                                  _selectedIndex = 0;
                                });
                              },
                              icon: Icon(
                                Icons.emoji_emotions_outlined,
                                color: _selectedIndex == 0
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          SizedBox(width: 5),
                          Container(
                            decoration: BoxDecoration(
                              color: _selectedIndex == 1
                                  ? Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              onPressed: () {
                                setState(() {
                                  _selectedIndex = 1;
                                });
                              },
                              icon: Icon(
                                Icons.gif_outlined,
                                color: _selectedIndex == 1
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  EmojiPickerWidget(
                    controller: widget.mesageController,
                    searchController: _searchController,
                    height: emojiHeight,
                  ),

                  // index 1: GIF
                  GiphyPickerWidget(
                    onGifSelected: (url) => widget.onSendGif(url, null),
                    onGifLongPress: _onGifLongPress,
                    searchController: _searchController,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
