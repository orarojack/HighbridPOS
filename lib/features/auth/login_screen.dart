// lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import 'auth_controller.dart';

/// The two sign-in modes offered by the login screen.
enum _LoginMode { staffPin, manager }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  _LoginMode _mode = _LoginMode.staffPin;

  // Staff PIN mode.
  final _staffId = TextEditingController();
  final _pin = TextEditingController();
  final _pinFocus = FocusNode();

  // Manager mode.
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _staffId.dispose();
    _pin.dispose();
    _pinFocus.dispose();
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _setMode(_LoginMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  Future<void> _submitPin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(authControllerProvider.notifier)
        .loginWithPin(_staffId.text, _pin.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = _pinErrorFor(result);
    });
  }

  String? _pinErrorFor(PinLoginResult result) {
    switch (result.outcome) {
      case PinLoginOutcome.ok:
        return null;
      case PinLoginOutcome.badCredentials:
        return 'Incorrect Staff ID or PIN.';
      case PinLoginOutcome.inactive:
        return 'This account is inactive.';
      case PinLoginOutcome.locked:
        final until = result.lockedUntil;
        if (until == null) return 'Account locked.';
        final hh = until.hour.toString().padLeft(2, '0');
        final mm = until.minute.toString().padLeft(2, '0');
        return 'Account locked until $hh:$mm';
    }
  }

  Future<void> _submitManager() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref
        .read(authControllerProvider.notifier)
        .login(_username.text, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('HighbridPOS',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  SegmentedButton<_LoginMode>(
                    segments: const [
                      ButtonSegment(
                        value: _LoginMode.staffPin,
                        label: Text('Staff PIN'),
                        icon: Icon(Icons.dialpad),
                      ),
                      ButtonSegment(
                        value: _LoginMode.manager,
                        label: Text('Manager'),
                        icon: Icon(Icons.admin_panel_settings),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => _setMode(s.first),
                  ),
                  const SizedBox(height: 20),
                  if (_mode == _LoginMode.staffPin)
                    ..._staffPinFields()
                  else
                    ..._managerFields(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy
                          ? null
                          : (_mode == _LoginMode.staffPin
                              ? _submitPin
                              : _submitManager),
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Sign in'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _staffPinFields() => [
        TextField(
          controller: _staffId,
          decoration: const InputDecoration(labelText: 'Staff ID'),
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          onSubmitted: (_) => _pinFocus.requestFocus(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pin,
          focusNode: _pinFocus,
          decoration: const InputDecoration(labelText: 'PIN'),
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _submitPin(),
        ),
      ];

  List<Widget> _managerFields() => [
        TextField(
          controller: _username,
          decoration: const InputDecoration(labelText: 'Username'),
          autofocus: true,
          onSubmitted: (_) => _passwordFocus.requestFocus(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          focusNode: _passwordFocus,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
          onSubmitted: (_) => _submitManager(),
        ),
      ];
}
