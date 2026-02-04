
import 'dart:ui';

import 'package:flutter/material.dart';

class LiquidGlass extends StatelessWidget {
  final Widget child;
  final double blur;
  final double borderRadius;
  final double? width;
  final double? height;
  final double opacity;
  final MainAxisAlignment? alignment;
  const LiquidGlass({
    super.key,
    required this.child,
    this.height,
    this.alignment,
    this.width,
    this.opacity = 0.2,
    this.blur = 10,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Use Neutral Colors for Frosted Glass effect
    final baseColor = isDark ? Colors.black : Colors.white;
    //    final baseColor = colorScheme.inversePrimary;

    final glassOpacity = isDark ? opacity : (opacity * 0.5);

    //    final borderColor = baseColor.withValues(alpha: isDark ? 0.1 : 0.05);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1) // Subtle light edge in dark mode
        : Colors.white.withValues(
            alpha: 0.4,
          ); // Stronger light edge in light mode

    Widget glassUI = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: RepaintBoundary(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: glassOpacity),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: borderColor, width: 1.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  // baseColor.withValues(alpha: isDark ? 0.25 : 0.15),
                  // baseColor.withValues(alpha: isDark ? 0.05 : 0.02),
                  baseColor.withValues(alpha: isDark ? 0.3 : 0.4),
                  baseColor.withValues(alpha: isDark ? 0.05 : 0.1),
                ],
              ),
              
            ),
            child: child,
          ),
        ),
      ),
    );

    if (alignment != null) {
      return Row(
        mainAxisAlignment: alignment!,
        mainAxisSize: MainAxisSize.min,
        children: [glassUI],
      );
    }
    return glassUI;
  }
}

// import 'package:flutter/material.dart';

// class LiquidGlass extends StatelessWidget {
//   final Widget child;
//   final double borderRadius;
//   final double? width;
//   final double? height;
//   final MainAxisAlignment? alignment;

//   const LiquidGlass({
//     super.key,
//     required this.child,
//     this.height,
//     this.alignment,
//     this.width,
//     required this.borderRadius,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final isDark = Theme.of(context).brightness == Brightness.dark;

//     // 🔧 TUNING THE LOOK FOR BOTH MODES

//     // LIGHT MODE: "Ice Block" (White tint, crisp)
//     // DARK MODE: "Smoked Glass" (Black tint, subtle)
//     final baseColor = isDark ? Colors.black : Colors.white;

//     // Opacity needs to be much lower in dark mode to not look "muddy"
//     final fillOpacity = isDark ? 0.2 : 0.35;

//     final borderColor = isDark
//         ? Colors.white.withValues(alpha: 0.1) // Subtle white edge in dark mode
//         : Colors.white.withValues(
//             alpha: 0.4,
//           ); // Strong white edge in light mode

//     Widget glassUI = Container(
//       width: width,
//       height: height,
//       decoration: BoxDecoration(
//         borderRadius: BorderRadius.circular(borderRadius),

//         // 1. The Tint
//         color: baseColor.withValues(alpha: fillOpacity),

//         // 2. The Border (Critical for the 3D look)
//         border: Border.all(color: borderColor, width: 1.5),

//         // 3. The Shine (Gradient)
//         gradient: LinearGradient(
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//           colors: isDark
//               ? [
//                   // Dark Mode Gradient (Subtle shine)
//                   Colors.white.withValues(alpha: 0.3),
//                   Colors.white.withValues(alpha: 0.1),
//                 ]
//               : [
//                   // Light Mode Gradient (Strong Ice Shine)
//                   Colors.white.withValues(alpha: 0.3),
//                   Colors.white.withValues(alpha: 0.1),
//                 ],
//         ),

//         // 4. Shadow (Keeps it floating)
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withValues(alpha: isDark ? 0.1 : 0.05),
//             blurRadius: 30,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: child,
//     );

//     if (alignment != null) {
//       Row(
//         mainAxisAlignment: MainAxisAlignment.center,
//         mainAxisSize: MainAxisSize.min,
//         children: [glassUI],
//       );
//     }
//     return glassUI;
//   }
// }