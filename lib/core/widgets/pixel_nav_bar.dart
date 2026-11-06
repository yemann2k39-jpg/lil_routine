import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/typography.dart';

/// Chunky pixel-style bottom navigation bar.
/// Items keep their state (used with IndexedStack) and squish when tapped.
class PixelNavBar extends StatelessWidget {
  const PixelNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onTap,
  });

  final List<PixelNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Palette.creamDeep,
        border: Border(top: BorderSide(color: Palette.outline, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(child: _Item(item: items[i], selected: i == index, onTap: () => onTap(i))),
            ],
          ),
        ),
      ),
    );
  }
}

class PixelNavItem {
  const PixelNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _Item extends StatefulWidget {
  const _Item({required this.item, required this.selected, required this.onTap});

  final PixelNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Palette.skySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? Palette.skyDeep : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.item.icon,
                size: 22,
                color: selected ? Palette.skyDeep : Palette.cocoaSoft,
              ),
              const SizedBox(height: 2),
              Text(
                widget.item.label,
                style: AppTypography.cozy(
                  11,
                  color: selected ? Palette.skyDeep : Palette.cocoaSoft,
                  weight: selected ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
