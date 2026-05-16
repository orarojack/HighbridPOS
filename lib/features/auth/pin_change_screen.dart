// lib/features/auth/pin_change_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import 'auth_controller.dart';

/// Screen for setting a new 6-digit PIN.
///
/// In [forced] mode (opened right after a login where the account still
/// requires a PIN change) it cannot be dismissed without completing the
/// change. In voluntary mode it offers a cancel.
class PinChangeScreen extends ConsumerStatefulWidget {
  const PinChangeScreen({super.key, this.forced = true});

  /// When true the screen has no cancel and cannot be popped.
  final bool forced;

  @override
  ConsumerState<PinChangeScreen> createState() => _PinChangeScreenState();
}

class _PinChangeScreenState extends ConsumerState<PinChangeScreen> {
  final _newPin = TextEditingController();
  final _confirmPin = TextEditingController();
  final _confirmFocus = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _newPin.dispose();
    _confirmPin.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newPin = _newPin.text;
    final confirm = _confirmPin.text;
    if (!RegExp(r'^\d{6}$').hasMatch(newPin)) {
      setState(() => _error = 'PIN must be exactly 6 digits.');
      return;
    }
    if (newPin != confirm) {
      setState(() => _error = 'The PINs do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final user = ref.read(authControllerProvider);
    if (user == null) {
      setState(() {
        _busy = false;
        _error = 'No signed-in user.';
      });
      return;
    }
    await ref.read(authRepositoryProvider).changePin(user.id, newPin);
    if (!mounted) return;
    if (widget.forced) {
      // Clearing the flag lets the app shell re-route to the home shell.
      ref.read(authControllerProvider.notifier).clearForcePinChange();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.forced,
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Change PIN',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(widget.forced
                        ? 'You must set a new PIN before continuing.'
                        : 'Set a new 6-digit PIN.'),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _newPin,
                      decoration: const InputDecoration(labelText: 'New PIN'),
                      obscureText: true,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onSubmitted: (_) => _confirmFocus.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmPin,
                      focusNode: _confirmFocus,
                      decoration:
                          const InputDecoration(labelText: 'Confirm new PIN'),
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save PIN'),
                      ),
                    ),
                    if (!widget.forced) ...[
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
