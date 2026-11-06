import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/typography.dart';

/// A card with a chunky pixel-style border and hard offset shadow.
class PixelCard extends StatelessWidget {
  const PixelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = Palette.paper,
    this.borderColor = Palette.outline,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Palette.shadow,
            offset: Offset(0, 4),
            blurRadius: 0,
          ),
        ],
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: card),
    );
  }
}

/// A big tappable pixel-style button that squishes on press.
class PixelButton extends StatelessWidget {
  const PixelButton({
    super.key,
    required this.label,
    this.onTap,
    this.color = Palette.skyDeep,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return _Squish(
      onTap: onTap,
      builder: (pressed) => Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.outline, width: 2),
          boxShadow: [
            BoxShadow(
              color: Palette.shadow,
              offset: pressed ? const Offset(0, 1) : const Offset(0, 4),
              blurRadius: 0,
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: Palette.paper),
              const SizedBox(width: 8),
            ],
            Text(
              label.toUpperCase(),
              style: AppTypography.pixelDisplay(12, color: Palette.paper),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round squishy icon button (e.g. the big glass "+" tap).
class PixelIconButton extends StatelessWidget {
  const PixelIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 64,
    this.color = Palette.skyDeep,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _Squish(
      onTap: onTap,
      builder: (pressed) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Palette.outline, width: 2),
          boxShadow: [
            BoxShadow(
              color: Palette.shadow,
              offset: pressed ? const Offset(0, 1) : const Offset(0, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: Icon(icon, size: size * 0.45, color: Palette.paper),
      ),
    );
  }
}

/// Wraps a child and squishes it (scale + shadow shift) while pressed.
class _Squish extends StatefulWidget {
  const _Squish({required this.builder, this.onTap});

  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;

  @override
  State<_Squish> createState() => _SquishState();
}

class _SquishState extends State<_Squish> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.builder(_pressed),
      ),
    );
  }
}
