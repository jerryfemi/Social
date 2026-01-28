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
    return Container(
      height: 400, // Increased height for search bar
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          // Search Bar & Tabs Row
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                // Search Toggle / Bar
                Expanded(
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
                            color: Theme.of(context).colorScheme.secondary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
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
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                              SizedBox(width: 20),

                              // Tabs
                              IconButton(
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
                              SizedBox(width: 10),
                              IconButton(
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
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),

          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                // index 0: Emoji
                // Note: External search for EmojiPicker is not fully integrated
                // as the package handles its own search view internally.
                // We could hide this and use our own but for now let's keep it simple.
                // The search bar in parent is mostly for GIFs.
                EmojiPickerWidget(
                  controller: widget.mesageController,
                  searchController: _searchController,
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
    );
  }
}
