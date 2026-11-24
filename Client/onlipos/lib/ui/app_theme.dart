/// アプリ全体の見た目（色・文字・ボタン・入力欄）。画面側で色や大きさを直接指定せず、ここの値を使う。
library;

import 'package:material_ui/material_ui.dart';

/// 意味を持つ色
class AppColors {
  static const primary = Color(0xFF1D5FD1);
  static const primarySoft = Color(0xFFE8F0FD);
  static const ink = Color(0xFF1B2430);
  static const secondary = Color(0xFF4A5566);
  static const muted = Color(0xFF647084);
  static const line = Color(0xFFDDE3EC);
  static const background = Color(0xFFF4F6FA);
  static const surface = Colors.white;

  static const success = Color(0xFF146C43);
  static const successSoft = Color(0xFFE3F5EC);
  static const warning = Color(0xFF8A5300);
  static const warningSoft = Color(0xFFFFF4DC);
  static const danger = Color(0xFFC0262D);
  static const dangerSoft = Color(0xFFFDEBEC);
}

// 日本語の字形で表示する（端末によって中国語の字形になるのを防ぐ）
const _fontFallback = [
  'Hiragino Sans',
  'Yu Gothic UI',
  'Meiryo',
  'Noto Sans CJK JP',
  'Noto Sans JP',
  'sans-serif',
];

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
    primary: AppColors.primary,
    error: AppColors.danger,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
  );
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
  );
  const buttonText = TextStyle(
    fontFamilyFallback: _fontFallback,
    fontSize: 17,
    fontWeight: FontWeight.bold,
  );
  const minSize = Size(64, 52);
  const padding = EdgeInsets.symmetric(horizontal: 20, vertical: 12);

  final base = ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamilyFallback: _fontFallback,
    visualDensity: VisualDensity.standard,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.line),
      ),
    ),
    // 目立たせるボタンはすべて同じ見た目にする
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFD6DCE6),
        disabledForegroundColor: const Color(0xFF7C8798),
        elevation: 0,
        minimumSize: minSize,
        padding: padding,
        textStyle: buttonText,
        shape: shape,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        disabledBackgroundColor: const Color(0xFFD6DCE6),
        disabledForegroundColor: const Color(0xFF7C8798),
        minimumSize: minSize,
        padding: padding,
        textStyle: buttonText,
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.surface,
        minimumSize: minSize,
        padding: padding,
        textStyle: buttonText.copyWith(fontSize: 16),
        side: const BorderSide(color: Color(0xFFB9C3D2)),
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(64, 48),
        textStyle: buttonText.copyWith(fontSize: 16),
        shape: shape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: Color(0xFFB9C3D2)),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: const TextStyle(
        fontFamilyFallback: _fontFallback,
        fontSize: 16,
        color: AppColors.ink,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      side: const BorderSide(color: Color(0xFFB9C3D2)),
    ),
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: 10,
      iconColor: AppColors.secondary,
      titleTextStyle: TextStyle(
        fontFamilyFallback: _fontFallback,
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: AppColors.ink,
      ),
      subtitleTextStyle: TextStyle(
        fontFamilyFallback: _fontFallback,
        fontSize: 14,
        color: AppColors.secondary,
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamilyFallback: _fontFallback,
        fontSize: 21,
        fontWeight: FontWeight.bold,
        color: AppColors.ink,
      ),
      contentTextStyle: TextStyle(
        fontFamilyFallback: _fontFallback,
        fontSize: 16,
        height: 1.6,
        color: AppColors.ink,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(
        fontFamilyFallback: _fontFallback,
        fontSize: 16,
        color: Colors.white,
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.secondary,
      indicatorColor: AppColors.primary,
      labelStyle: TextStyle(
        fontFamilyFallback: _fontFallback,
        fontSize: 17,
        fontWeight: FontWeight.bold,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamilyFallback: _fontFallback,
        fontSize: 17,
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line),
  );
}
