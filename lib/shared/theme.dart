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
