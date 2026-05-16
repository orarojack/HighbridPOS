// lib/features/pos/payment_dialog.dart
import 'package:flutter/material.dart';

import '../../domain/sale_calculator.dart';
import '../../shared/money.dart';

/// Cash-payment dialog. Resolves to the tendered amount in cents, or null
/// if cancelled.
class PaymentDialog extends StatefulWidget {
  const PaymentDialog({super.key, required this.total});
  final int total;

  static Future<int?> show(BuildContext context, int total) =>
      showDialog<int>(
        context: context,
        builder: (_) => PaymentDialog(total: total),
      );

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final _tendered = TextEditingController();

  @override
  void dispose() {
    _tendered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tendered = parseMoney(_tendered.text);
    final sufficient = tendered != null &&
        isSufficientTender(tendered: tendered, total: widget.total);
    final change = sufficient
        ? changeDue(tendered: tendered, total: widget.total)
        : 0;

    return AlertDialog(
      title: const Text('Cash payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total due'),
              Text(formatMoney(widget.total),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tendered,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Cash tendered'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Change due'),
              Text(formatMoney(change),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              sufficient ? () => Navigator.of(context).pop(tendered) : null,
          child: const Text('Complete sale'),
        ),
      ],
    );
  }
}
