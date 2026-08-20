import 'package:flutter/material.dart';

/// 护眼暖色主题：低饱和背景、大圆角、高对比按钮、≥20sp 正文字号。
/// 适配低龄娃娃平板使用。
class AppTheme {
  static ThemeData get light {
    const primary = Color(0xFF5B8C5A);   // 柔和绿
    const surface = Color(0xFFFDF8F0);   // 暖白
    const cardBg = Color(0xFFFFFBF3);
    const textColor = Color(0xFF3D3D3D);

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        surface: surface,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: surface,
      cardTheme: const CardThemeData(
        color: cardBg,
        elevation: 1,
        margin: EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      textTheme: const TextTheme(
        // ≥20sp 正文，低龄友好
        bodyLarge: TextStyle(fontSize: 20, color: textColor),
        bodyMedium: TextStyle(fontSize: 18, color: textColor),
        titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
        titleMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: textColor),
        labelLarge: TextStyle(fontSize: 20, color: Colors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(88, 52),
          textStyle: const TextStyle(fontSize: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        labelStyle: const TextStyle(fontSize: 16),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
    );
  }
}
