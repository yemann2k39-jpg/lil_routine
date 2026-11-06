import 'package:flutter/material.dart';

/// A chunky pixel-art cup/glass, drawn programmatically (crisp at any size).
/// Placeholder art: one design for all drink slots for now — per-slot cup
/// designs come in the LIL-12 polish pass.
class PixelCup extends StatelessWidget {
  const PixelCup({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _CupPainter());
  }
}

class _CupPainter extends CustomPainter {
  // Palette (sky family, matches the app).
  static const glassBody = Color(0xFFFFFBF4); // empty glass = paper
  static const water = Color(0xFF9FC4E8); // water fill
  static const waterLight = Color(0xFFC4DEF2); // water surface highlight
  static const outline = Color(0xFF4E6E8E); // cool deep blue outline

  // 12 cols x 13 rows; per-row [minCol, maxCol]; cup tapers towards bottom.
  static const _rows = <int, List<int>>{
    0: [1, 10],
    1: [1, 10],
    2: [1, 10],
    3: [1, 10],
    4: [1, 10],
    5: [1, 10],
    6: [2, 9],
    7: [2, 9],
    8: [2, 9],
    9: [3, 8],
    10: [3, 8],
    11: [3, 8],
    12: [4, 7],
  };

  static const _waterStartRow = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final px = size.width / 12;
    final py = size.height / 13;

    void cell(double x, double y, Color c) {
      canvas.drawRect(
        Rect.fromLTWH(x * px, y * py, px, py),
        Paint()..color = c,
      );
    }

    for (final entry in _rows.entries) {
      final y = entry.key;
      final min = entry.value[0];
      final max = entry.value[1];
      final isBottom = y == _rows.length - 1;
      for (var x = min; x <= max; x++) {
        final isEdge = x == min || x == max || y == 0 || isBottom;
        Color c;
        if (isEdge) {
          c = outline;
        } else if (y >= _waterStartRow) {
          c = water;
        } else {
          c = glassBody;
        }
        cell(x.toDouble(), y.toDouble(), c);
      }
      // Water surface highlight on the first water row.
      if (y == _waterStartRow) {
        cell((min + 1).toDouble(), y.toDouble(), waterLight);
        cell((min + 2).toDouble(), y.toDouble(), waterLight);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CupPainter oldDelegate) => false;
}
