import 'package:flutter/material.dart';
import 'palette.dart';

/// Typography: Silkscreen (pixel) for headings/numbers, Varela Round
/// for cozy body text.
abstract final class AppTypography {
  static const pixel = 'Pixel';
  static const body = 'CozyBody';

  static TextStyle pixelDisplay(double size, {Color? color}) => TextStyle(
        fontFamily: pixel,
        fontWeight: FontWeight.w700,
        fontSize: size,
        height: 1.2,
        color: color ?? Palette.cocoa,
        letterSpacing: 0.5,
      );

  static TextStyle pixelNumber(double size, {Color? color}) => TextStyle(
        fontFamily: pixel,
        fontWeight: FontWeight.w400,
        fontSize: size,
        height: 1.1,
        color: color ?? Palette.cocoa,
      );

  static TextStyle cozy(double size, {Color? color, FontWeight? weight}) =>
      TextStyle(
        fontFamily: body,
        fontSize: size,
        height: 1.35,
        color: color ?? Palette.cocoa,
        fontWeight: weight,
      );
}
