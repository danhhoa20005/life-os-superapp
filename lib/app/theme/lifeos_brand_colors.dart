import 'package:flutter/material.dart';

/// Official LifeOS BrandKit 1.0 Design Tokens (`06_Design_Tokens/LifeOS_Flutter_BrandColors.dart`).
/// Tagline: "Một ứng dụng. Cả cuộc sống."
abstract final class LifeOSBrandColors {
  static const primary = Color(0xFF0B7A2A);
  static const primaryLight = Color(0xFF55D52F);
  static const primaryDark = Color(0xFF03602B);
  static const forest = Color(0xFF113824);
  static const mint = Color(0xFFE7F7EB);
  static const ink = Color(0xFF1D1D1F);
  static const background = Color(0xFFF7F8F9);

  // Official Multi-stop Gradients from `LifeOS_BrandKit/01_Vector_SVG/`
  static const List<Color> houseGradient = [
    Color(0xFF56D831),
    Color(0xFF20B72E),
    Color(0xFF007E30),
  ];

  static const List<double> houseStops = [0.0, 0.47, 1.0];

  static const List<Color> leftLeafGradient = [
    Color(0xFF84DE24),
    Color(0xFF23B834),
  ];

  static const List<Color> rightLeafGradient = [
    Color(0xFF0AAA37),
    Color(0xFF006B2D),
  ];

  static const List<Color> appIconBgGradient = [
    Color(0xFF65DD30),
    Color(0xFF22B72D),
    Color(0xFF006D2D),
  ];

  static const List<double> appIconBgStops = [0.0, 0.45, 1.0];
}
