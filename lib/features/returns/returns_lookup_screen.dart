// lib/features/returns/returns_lookup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'return_controller.dart';
import 'return_select_screen.dart';

/// Step 1 of the returns flow: look up an original sale by its reference
/// number. On a match the user is routed to the [ReturnSelectScreen]; an
/// unknown reference shows a clear inline message.
class ReturnsLookupScreen extends ConsumerStatefulWidget {
  const ReturnsLookupScreen({super.key});

  @override
  ConsumerState<ReturnsLookupScreen> createState() =>
      _ReturnsLookupScreenState();
}

class _ReturnsLookupScreenState extends ConsumerState<ReturnsLookupScreen> {
  final _reference = TextEditingController();
  bool _searching = false;
  bool _notFound = false;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _findSale() async {
    final reference = _reference.text.trim();
    if (reference.isEmpty) return;

    setState(() {
      _searching = true;
      _notFound = false;
    });

    final controller = ref.read(returnControllerProvider.notifier);
    await controller.loadSale(reference);
    if (!mounted) return;

    final draft = ref.read(returnControllerProvider).valueOrNull;
    setState(() => _searching = false);

    if (draft == null) {
      setState(() => _notFound = true);
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ReturnSelectScreen()),
    );
    // Back from the select screen: drop the draft so a new lookup starts clean.
    ref.read(returnControllerProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Returns')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.assignment_return,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('Find the original sale',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the sale reference number from the customer receipt.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _reference,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Sale reference number',
                      prefixIcon: Icon(Icons.receipt_long),
                    ),
                    onChanged: (_) {
                      if (_notFound) setState(() => _notFound = false);
                    },
                    onSubmitted: (_) => _findSale(),
                  ),
                  if (_notFound) ...[
                    const SizedBox(height: 12),
                    Text(
                      'No sale found for that reference number.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      icon: _searching
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      label: const Text('Find sale'),
                      onPressed: _searching ? null : _findSale,
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
}
