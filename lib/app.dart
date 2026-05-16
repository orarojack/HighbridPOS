// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/pin_change_screen.dart';
import 'features/home_shell.dart';
import 'shared/theme.dart';

class HighbridPosApp extends ConsumerWidget {
  const HighbridPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    final Widget home;
    if (user == null) {
      home = const LoginScreen();
    } else if (user.forcePinChange) {
      home = const PinChangeScreen();
    } else {
      home = const HomeShell();
    }
    return MaterialApp(
      title: 'HighbridPOS',
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    );
  }
}
