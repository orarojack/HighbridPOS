// lib/features/auth/lock_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import 'auth_controller.dart';

/// A quick-lock overlay shown over the home shell.
///
/// It re-verifies the *currently signed-in* user before dismissing. The user
/// is never logged out — [authControllerProvider] state is retained — so
/// re-entry must match the same user's credentials. A user with a PIN enters
/// their Staff ID + 6-digit PIN; a manager without a PIN enters their
/// username + password. Wrong or mismatched credentials show an inline error.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});

  /// Called once correct re-entry for the signed-in user is confirmed.
  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  // PIN re-entry (Staff ID + PIN).
  final _staffId = TextEditingController();
  final _pin = TextEditingController();

  // Password re-entry (manager without a PIN).
  final _password = TextEditingController();

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _staffId.dispose();
    _pin.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _hasPinCredentials =>
      _staffId.text.trim().isNotEmpty && _pin.text.isNotEmpty;

  bool get _hasPasswordCredentials => _password.text.isNotEmpty;

  Future<void> _unlock() async {
    final current = ref.read(authControllerProvider);
    if (current == null) return; // logged out from elsewhere; nothing to do.

    setState(() {
      _busy = true;
      _error = null;
    });

    final auth = ref.read(authRepositoryProvider);
    AppUser? user;
    String? error;

    if (_hasPinCredentials) {
      final result =
          await auth.loginWithPin(_staffId.text.trim(), _pin.text);
      switch (result.outcome) {
        case PinLoginOutcome.ok:
          user = result.user;
        case PinLoginOutcome.badCredentials:
          error = 'Incorrect Staff ID or PIN.';
        case PinLoginOutcome.locked:
          error = 'That account is locked. Try again later.';
        case PinLoginOutcome.inactive:
          error = 'That account is inactive.';
      }
    } else if (_hasPasswordCredentials) {
      user = await auth.login(current.username, _password.text);
      if (user == null) {
        error = 'Incorrect password.';
      }
    } else {
      error = 'Enter your PIN or password to unlock.';
    }

    // Re-entry must be the SAME signed-in user — a different valid account
    // cannot bypass the lock.
    if (user != null && user.id != current.id) {
      error = 'These credentials are not for the locked account.';
      user = null;
    }

    if (!mounted) return;

    if (user != null) {
      widget.onUnlocked();
      return;
    }

    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider);
    if (user == null) return const SizedBox.shrink();

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_outline,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('Locked',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text('Signed in as ${user.fullName}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _staffId,
                    decoration: const InputDecoration(labelText: 'Staff ID'),
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pin,
                    decoration: const InputDecoration(labelText: 'PIN'),
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _busy ? null : _unlock(),
                  ),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('or'),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _busy ? null : _unlock(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _unlock,
                    icon: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_open),
                    label: const Text('Unlock'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
