// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/home_shell.dart';
import 'shared/theme.dart';

class HighbridPosApp extends ConsumerWidget {
  const HighbridPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    return MaterialApp(
      title: 'HighbridPOS',
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      home: user == null ? const LoginScreen() : const HomeShell(),
    );
  }
}
