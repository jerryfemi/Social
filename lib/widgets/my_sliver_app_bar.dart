import 'package:flutter/material.dart';

class MyAppBar extends StatelessWidget {
  final Widget? title;
  final bool isSelection;
  final String text;
  final void Function()? onPresed;
  const MyAppBar({
    super.key,
    required this.text,
    this.title,
    this.isSelection = false,
    required this.onPresed,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 100,
      centerTitle: true,
      title: title,
      actions: [
        if (isSelection == true) Text(text),
        IconButton(
          onPressed: onPresed,
          icon: Icon(
            Icons.add_circle_outline_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
      floating: false,
      pinned: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: Text(
          'Chats',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
