// lib/shared/manager_approval.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/auth_repository.dart';
import '../domain/models.dart';
import '../providers.dart';

/// Shows a manager-approval dialog for the given [action] and returns the
/// approving manager/admin [AppUser] on success, or null if cancelled.
///
/// The dialog accepts either a Staff ID + PIN (validated via
/// [AuthRepository.loginWithPin]) or a username + password (validated via
/// [AuthRepository.login]). Only a user whose role satisfies
/// `UserRole.canManageProducts` is accepted; a cashier credential is rejected
/// with an inline message.
Future<AppUser?> requestManagerApproval(
  BuildContext context,
  WidgetRef ref, {
  required String action,
}) {
  return showDialog<AppUser>(
    context: context,
    builder: (_) => _ManagerApprovalDialog(
      auth: ref.read(authRepositoryProvider),
      action: action,
    ),
  );
}

class _ManagerApprovalDialog extends StatefulWidget {
  const _ManagerApprovalDialog({required this.auth, required this.action});

  final AuthRepository auth;
  final String action;

  @override
  State<_ManagerApprovalDialog> createState() => _ManagerApprovalDialogState();
}

class _ManagerApprovalDialogState extends State<_ManagerApprovalDialog> {
  final _staffId = TextEditingController();
  final _pin = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _staffId.dispose();
    _pin.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _hasPinCredentials =>
      _staffId.text.trim().isNotEmpty && _pin.text.isNotEmpty;

  bool get _hasPasswordCredentials =>
      _username.text.trim().isNotEmpty && _password.text.isNotEmpty;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    AppUser? user;
    String? error;

    if (_hasPinCredentials) {
      final result =
          await widget.auth.loginWithPin(_staffId.text.trim(), _pin.text);
      switch (result.outcome) {
        case PinLoginOutcome.ok:
          user = result.user;
        case PinLoginOutcome.badCredentials:
          error = 'Invalid Staff ID or PIN.';
        case PinLoginOutcome.locked:
          error = 'That account is locked. Try again later.';
        case PinLoginOutcome.inactive:
          error = 'That account is inactive.';
      }
    } else if (_hasPasswordCredentials) {
      user = await widget.auth.login(
        _username.text.trim(),
        _password.text,
      );
      if (user == null) {
        error = 'Invalid username or password.';
      }
    } else {
      error = 'Enter a Staff ID + PIN or a username + password.';
    }

    if (user != null && !user.role.canManageProducts) {
      error = 'That account is not a manager or admin.';
      user = null;
    }

    if (!mounted) return;

    if (user != null) {
      Navigator.of(context).pop(user);
      return;
    }

    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Approve: ${widget.action}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('A manager or admin must approve this action.'),
            const SizedBox(height: 16),
            TextField(
              controller: _staffId,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Staff ID'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pin,
              decoration: const InputDecoration(labelText: 'PIN'),
              obscureText: true,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            TextField(
              controller: _username,
              decoration: const InputDecoration(labelText: 'Username'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              onSubmitted: (_) => _submit(),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || !(_hasPinCredentials || _hasPasswordCredentials)
              ? null
              : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Approve'),
        ),
      ],
    );
  }
}
