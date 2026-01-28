import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';

class EmojiPickerWidget extends StatefulWidget {
  final TextEditingController controller;
  final ScrollController? scrollController;
  final TextEditingController? searchController;

  const EmojiPickerWidget({
    super.key,
    required this.controller,
    this.scrollController,
    this.searchController,
  });

  @override
  State<EmojiPickerWidget> createState() => _EmojiPickerWidgetState();
}

class _EmojiPickerWidgetState extends State<EmojiPickerWidget> {
  List<Emoji> _filteredEmojis = [];

  @override
  void initState() {
    super.initState();
    widget.searchController?.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    widget.searchController?.removeListener(_onSearchChanged);
    super.dispose();
  }

  void _onSearchChanged() {
    final query = widget.searchController?.text.toLowerCase().trim() ?? '';
    if (query.isEmpty) {
      if (_filteredEmojis.isNotEmpty) {
        setState(() {
          _filteredEmojis = [];
        });
      }
      return;
    }

    final allEmojis = defaultEmojiSet
        .expand((element) => element.emoji)
        .toList();
    final matches = allEmojis
        .where((e) => e.name.toLowerCase().contains(query))
        .toList();

    setState(() {
      _filteredEmojis = matches;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.searchController != null &&
        widget.searchController!.text.isNotEmpty &&
        _filteredEmojis.isNotEmpty) {
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: _filteredEmojis.length,
        itemBuilder: (context, index) {
          final emoji = _filteredEmojis[index];
          return GestureDetector(
            onTap: () {
              widget.controller.text = widget.controller.text + emoji.emoji;
              widget.controller.selection = TextSelection.fromPosition(
                TextPosition(offset: widget.controller.text.length),
              );
            },
            child: Center(
              child: Text(emoji.emoji, style: const TextStyle(fontSize: 28)),
            ),
          );
        },
      );
    } else if (widget.searchController != null &&
        widget.searchController!.text.isNotEmpty &&
        _filteredEmojis.isEmpty) {
      return const Center(child: Text("No emojis found"));
    }

    return EmojiPicker(
      // text interaction
      textEditingController: widget.controller,
      scrollController: widget.scrollController,

      //
      onEmojiSelected: (category, emoji) {
        widget.controller.text = widget.controller.text + emoji.emoji;
        widget.controller.selection = TextSelection.fromPosition(
          TextPosition(offset: widget.controller.text.length),
        );
      },
      onBackspacePressed: () {},

      config: Config(
        height: 256,
        checkPlatformCompatibility: true,

        // view configuration
        emojiViewConfig: EmojiViewConfig(
          columns: 7,
          emojiSizeMax:
              28 *
              (foundation.defaultTargetPlatform == TargetPlatform.iOS
                  ? 1.30
                  : 1.0),
          backgroundColor: Theme.of(context).cardColor,

          // grid look
          gridPadding: EdgeInsets.zero,
          horizontalSpacing: 0,
          verticalSpacing: 0,
        ),

        // category bar configuration
        categoryViewConfig: CategoryViewConfig(
          initCategory: Category.RECENT,
          backgroundColor: Theme.of(context).cardColor,
          indicatorColor: Theme.of(context).colorScheme.primary,
          dividerColor: Theme.of(context).colorScheme.outlineVariant,
          backspaceColor: Theme.of(context).colorScheme.primary,
          categoryIcons: CategoryIcons(
            recentIcon: Icons.access_time_filled_rounded,
            smileyIcon: Icons.emoji_emotions_rounded,
            animalIcon: Icons.pets_rounded,
            foodIcon: Icons.fastfood_rounded,
            activityIcon: Icons.directions_run_rounded,
            travelIcon: Icons.location_on_rounded,
            objectIcon: Icons.lightbulb_rounded,
            symbolIcon: Icons.emoji_symbols_rounded,
            flagIcon: Icons.flag_rounded,
          ),
        ),

        // Search cofiguration
        searchViewConfig: SearchViewConfig(
          backgroundColor: Theme.of(context).cardColor,
          buttonIconColor: Theme.of(context).colorScheme.onSurfaceVariant,
        ),

        // buttom bar config
        // Enable it just in case user wants internal navigation
        bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
      ),
    );
  }
}
