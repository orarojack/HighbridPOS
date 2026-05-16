// lib/shared/theme.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF004224),
    brightness: Brightness.light,
  ).copyWith(
    surface: const Color(0xFFFFFFFF),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFFFFFFF),
    // The design spec puts the deep forest green on the app bar; Material 3
    // would otherwise tint it near-white from the surface colour.
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF004224),
      foregroundColor: Color(0xFFFFFFFF),
      elevation: 0,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
  );
}

final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');
final _dayFmt = DateFormat('EEEE, d MMMM yyyy');

String formatDateTime(DateTime dt) => _dateFmt.format(dt);
String formatDay(DateTime dt) => _dayFmt.format(dt);
