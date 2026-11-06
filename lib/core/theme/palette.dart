import 'package:flutter/material.dart';

/// LilRoutine cozy palette.
/// Warm, soft, low-contrast: cream base, water-blue + peach accents,
/// dusty pink highlights, soft brown text.
abstract final class Palette {
  // Base surfaces
  static const cream = Color(0xFFFFF6EC); // app background
  static const creamDeep = Color(0xFFFCEBD9); // cards, sheets
  static const paper = Color(0xFFFFFBF4); // raised surfaces

  // Accents
  static const sky = Color(0xFFA9C9E8); // water / calm blue
  static const skyDeep = Color(0xFF6E96BE); // primary action blue
  static const skySoft = Color(0xFFDCEAF6); // tinted fills
  static const peach = Color(0xFFF7B98B); // food / energy
  static const peachDeep = Color(0xFFE89A63);
  static const peachSoft = Color(0xFFFBDCBC); // light peach tone
  static const blush = Color(0xFFF3A7B4); // habits / streaks
  static const blushDeep = Color(0xFFD97C8E);

  // Text & structure
  static const cocoa = Color(0xFF5A4636); // primary text
  static const cocoaSoft = Color(0xFF8A7461); // secondary text
  static const outline = Color(0xFFE3D2BC); // chunky pixel borders
  static const shadow = Color(0xFFEAD8C0); // hard pixel shadow

  // States
  static const success = skyDeep;
  static const warning = peachDeep;
  static const locked = cocoaSoft;
}
