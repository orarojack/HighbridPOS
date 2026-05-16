// lib/features/pos/discount_dialog.dart
import 'package:flutter/material.dart';

import '../../domain/discount_calculator.dart';
import '../../shared/money.dart';

/// Shows a discount-entry dialog for a single cart line.
///
/// The user toggles between Amount and Percent mode and enters a value.
/// On confirm, the entry is resolved to cents via [resolveDiscount] and
/// returned. Returns null if cancelled.
///
/// Validation rules (inline error, confirm disabled):
/// - Amount mode: value must be >= 0.
/// - Percent mode: value must be 0–100.
///
/// The dialog does NOT perform the manager-approval check; that is the
/// responsibility of the caller (Task 6, Sell screen).
Future<int?> showDiscountDialog(
  BuildContext context, {
  required int lineSubtotal,
  required int currentDiscount,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _DiscountDialog(
      lineSubtotal: lineSubtotal,
      currentDiscount: currentDiscount,
    ),
  );
}

class _DiscountDialog extends StatefulWidget {
  const _DiscountDialog({
    required this.lineSubtotal,
    required this.currentDiscount,
  });

  final int lineSubtotal;
  final int currentDiscount;

  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  final _valueController = TextEditingController();
  bool _isPercent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-fill with the current discount as an amount (only if non-zero).
    if (widget.currentDiscount > 0) {
      _valueController.text = formatMoney(widget.currentDiscount);
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  /// Parses the text field into a non-negative [double], or null on failure.
  double? get _parsedValue {
    final trimmed = _valueController.text.trim();
    if (trimmed.isEmpty) return null;
    final v = double.tryParse(trimmed);
    if (v == null || v < 0) return null;
    return v;
  }

  String? _validate() {
    final v = _parsedValue;
    if (v == null) return 'Enter a valid number.';
    if (_isPercent && v > 100) return 'Percent must be 0–100.';
    return null;
  }

  void _onConfirm() {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final cents = resolveDiscount(
      lineSubtotal: widget.lineSubtotal,
      isPercent: _isPercent,
      value: _parsedValue!,
    );
    if (!mounted) return;
    Navigator.of(context).pop(cents);
  }

  bool get _canConfirm => _validate() == null;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Line discount'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Line subtotal'),
              Text(
                formatMoney(widget.lineSubtotal),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Amount')),
              ButtonSegment(value: true, label: Text('Percent')),
            ],
            selected: {_isPercent},
            onSelectionChanged: (selection) {
              setState(() {
                _isPercent = selection.first;
                _error = null;
                // Clear the field on mode switch so stale values don't confuse.
                _valueController.clear();
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _valueController,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _isPercent ? 'Discount (%)' : 'Discount amount',
              suffixText: _isPercent ? '%' : null,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _onConfirm(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canConfirm ? _onConfirm : null,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
