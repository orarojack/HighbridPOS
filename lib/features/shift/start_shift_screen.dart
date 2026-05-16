// lib/features/shift/start_shift_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/shift_repository.dart';
import '../../shared/money.dart';
import 'shift_controller.dart';

/// Opening-float entry that starts a shift for the signed-in user.
class StartShiftScreen extends ConsumerStatefulWidget {
  const StartShiftScreen({super.key, this.onStarted});

  /// Called after the shift opens successfully. The Sell-screen gate uses this
  /// to drop back into the sale UI.
  final VoidCallback? onStarted;

  @override
  ConsumerState<StartShiftScreen> createState() => _StartShiftScreenState();
}

class _StartShiftScreenState extends ConsumerState<StartShiftScreen> {
  final _floatController = TextEditingController(text: '0.00');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final cents = parseMoney(_floatController.text);
    if (cents == null) {
      setState(() => _error = 'Enter a valid opening-float amount.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(shiftControllerProvider.notifier).start(cents);
      if (!mounted) return;
      widget.onStarted?.call();
    } on ShiftAlreadyOpenException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'A shift is already open for this user.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not start the shift: $e';
      });
    }
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.play_circle_outline,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('Start shift',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text('Count the cash drawer and enter the opening float.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _floatController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Opening float',
                      prefixText: 'KSh ',
                    ),
                    onSubmitted: (_) => _busy ? null : _start(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _start,
                    icon: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: const Text('Start shift'),
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
