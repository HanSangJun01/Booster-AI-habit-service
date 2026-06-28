import 'package:flutter/material.dart';

/// Booster 디자인 토큰 (HTML 목업 기준)
class BC {
  // primary orange
  static const o1 = Color(0xFFFF7A2E);
  static const o2 = Color(0xFFFF4D06);
  static const oMain = Color(0xFFFF5C00);
  static const oSoft = Color(0xFFFFF1E8);
  static const oSoft2 = Color(0xFFFFE7D6);

  // accents
  static const blue = Color(0xFF2E7DF0);
  static const blueSoft = Color(0xFFEAF1FE);
  static const green = Color(0xFF6FBF3D);
  static const greenSoft = Color(0xFFEEF7E6);

  // coin gold
  static const gold1 = Color(0xFFFFD24D);
  static const gold2 = Color(0xFFF5A623);

  // neutrals
  static const ink = Color(0xFF1A1A1A);
  static const ink2 = Color(0xFF5A5A5E);
  static const ink3 = Color(0xFF9A9AA0);
  static const line = Color(0xFFEFEFF1);
  static const bg = Color(0xFFF6F6F7);
  static const card = Color(0xFFFFFFFF);
  static const tagBg = Color(0xFFF2F1EF);

  static const grad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [o1, o2],
  );
  static const heroGrad = LinearGradient(
    begin: Alignment(-0.6, -1),
    end: Alignment(0.8, 1),
    colors: [o1, o2],
  );

  static List<BoxShadow> cardShadow = [
    BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 16, offset: const Offset(0, 4)),
  ];
  static List<BoxShadow> ctaShadow = [
    BoxShadow(color: const Color(0xFFFF4D06).withOpacity(.32), blurRadius: 20, offset: const Offset(0, 8)),
  ];
}

class BoosterTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: BC.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BC.oMain,
        primary: BC.oMain,
        background: BC.bg,
      ),
      fontFamily: 'Pretendard',
      splashFactory: InkRipple.splashFactory,
      textTheme: const TextTheme().apply(bodyColor: BC.ink, displayColor: BC.ink),
    );
  }
}
