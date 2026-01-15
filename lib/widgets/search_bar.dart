import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class SearchBarDelegate extends SliverPersistentHeaderDelegate {
  final double _maxExtentHeight = 60; // Slightly taller for better touch area
  final void Function(String)? onChanged;
  final TextEditingController controller;

  SearchBarDelegate({required this.onChanged, required this.controller});

  @override
  double get minExtent => 0; // Collapses completely

  @override
  double get maxExtent => _maxExtentHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);

    // Logic: As we scroll down, the bar slides UP and fades OUT
    final offsetY = -progress * _maxExtentHeight;

    return Transform.translate(
      offset: Offset(0, offsetY),
      child: Opacity(
        opacity: 1 - progress,
        child: Container(
          color: Theme.of(
            context,
          ).colorScheme.surface, // Background to cover list
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: CupertinoSearchTextField(
            onChanged: onChanged,
            controller: controller,
            placeholder: 'Search users...',
            placeholderStyle: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),

            backgroundColor: Theme.of(
              context,
            ).colorScheme.secondary, // Make it pop slightly
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(SearchBarDelegate oldDelegate) {
    return oldDelegate.controller != controller;
  }
}
