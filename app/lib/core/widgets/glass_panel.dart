import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Frosted-glass container for UI panels.
///
/// Use it for overlays (question panel, dialogs) only — never on top of the
/// map, where a live blur is too expensive for low-end phones. Set
/// [blur] to false to get the same look without the BackdropFilter.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.blur = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: radius,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (!blur) return panel;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: panel,
      ),
    );
  }
}
