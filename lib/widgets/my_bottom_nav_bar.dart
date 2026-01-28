import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:social/widgets/liquid_glass.dart';

class MyBottomNavBar extends StatelessWidget {
  const MyBottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    int currentIndex = 0;

    if (location.startsWith('/home')) currentIndex = 0;
    if (location.startsWith('/settings')) currentIndex = 1;

    return SafeArea(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          LiquidGlass(
            borderRadius: 40,
            // blur: 10,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: GNav(
                iconSize: 30,
                haptic: true,
                color: Theme.of(context).colorScheme.tertiary,
                activeColor: Theme.of(context).colorScheme.primary,
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                gap: 8,
                textStyle: TextStyle(fontSize: 16),
                onTabChange: (index) {
                  switch (index) {
                    case 0:
                      context.go('/home');
                      break;
                    case 1:
                      context.go('/settings');
                      break;
                  }
                },
                selectedIndex: currentIndex,
                tabBackgroundColor: Theme.of(
                  context,
                ).colorScheme.secondary.withValues(alpha: 0.15),
                tabs: const [
                  GButton(icon: Icons.home_rounded, text: 'Home'),
                  GButton(icon: Icons.settings, text: 'Settings'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
