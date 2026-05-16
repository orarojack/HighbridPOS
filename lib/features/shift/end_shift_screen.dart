// lib/features/shift/end_shift_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../domain/shift_calculator.dart';
import '../../providers.dart';
import '../../shared/manager_approval.dart';
import '../../shared/money.dart';
import '../auth/auth_controller.dart';
import 'shift_controller.dart';
import 'shift_summary.dart';

/// Counts the drawer, shows the live variance, and closes the open [shift].
/// A non-zero variance requires manager approval; the approver is recorded as
/// `closedBy`. On a successful close [onClosed] is called with the resulting
/// [ShiftSummary] so a parent can show it after the controller drops the shift.
class EndShiftScreen extends ConsumerStatefulWidget {
  const EndShiftScreen({super.key, required this.shift, this.onClosed});

  final Shift shift;

  /// Called once the shift has closed, with its summary.
  final ValueChanged<ShiftSummary>? onClosed;

  @override
  ConsumerState<EndShiftScreen> createState() => _EndShiftScreenState();
}

class _EndShiftScreenState extends ConsumerState<EndShiftScreen> {
  final _countedController = TextEditingController();
  final _noteController = TextEditingController();
  String? _error;
  bool _busy = false;
  ShiftSummary? _summary;

  int get _expected => expectedCash(
        openingFloat: widget.shift.openingFloat,
        cashSales: widget.shift.cashSalesTotal,
        payIn: widget.shift.payInTotal,
        payOut: widget.shift.payOutTotal,
      );

  /// Live variance for the amount currently typed, or null if not a number.
  int? get _liveVariance {
    final counted = parseMoney(_countedController.text);
    if (counted == null) return null;
    return cashVariance(counted: counted, expected: _expected);
  }

  @override
  void dispose() {
    _countedController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    final counted = parseMoney(_countedController.text);
    if (counted == null) {
      setState(() => _error = 'Enter a valid counted-cash amount.');
      return;
    }
    final variance = cashVariance(counted: counted, expected: _expected);

    // The cashier closes a balanced drawer; a non-zero variance needs a
    // manager/admin to approve, and that approver becomes `closedBy`.
    var closedBy = ref.read(authControllerProvider)!.id;
    if (variance != 0) {
      final approver = await requestManagerApproval(
        context,
        ref,
        action: 'Close shift with a ${formatMoney(variance)} variance',
      );
      if (approver == null) return; // cancelled — shift stays open.
      closedBy = approver.id;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final closed = await ref.read(shiftControllerProvider.notifier).end(
            shiftId: widget.shift.id,
            countedCash: counted,
            note: _noteController.text.trim(),
            closedBy: closedBy,
          );
      final summary =
          await ref.read(shiftRepositoryProvider).shiftSummary(closed.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _summary = summary;
      });
      widget.onClosed?.call(summary);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not close the shift: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (summary != null) {
      return Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ShiftSummaryView(summary: summary),
            ),
          ),
        ),
      );
    }

    final variance = _liveVariance;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('End shift',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 16),
                    _Row(
                        label: 'Opening float',
                        value: widget.shift.openingFloat),
                    _Row(
                        label: 'Cash sales',
                        value: widget.shift.cashSalesTotal),
                    _Row(label: 'Pay-in', value: widget.shift.payInTotal),
                    _Row(label: 'Pay-out', value: widget.shift.payOutTotal),
                    const Divider(height: 24),
                    _Row(
                        label: 'Expected cash',
                        value: _expected,
                        bold: true),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _countedController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Counted cash',
                        prefixText: 'KSh ',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Variance',
                            style:
                                TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          variance == null ? '—' : formatMoney(variance),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: (variance ?? 0) != 0
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                        ),
                      ],
                    ),
                    if (variance != null && variance != 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'A non-zero variance needs manager approval to close.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: TextStyle(
                              color:
                                  Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy ? null : _close,
                      icon: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : const Icon(Icons.stop_circle_outlined),
                      label: const Text('Close shift'),
                    ),
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

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.bold = false});
  final String label;
  final int value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        fontSize: bold ? 16 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(formatMoney(value), style: style),
        ],
      ),
    );
  }
}
