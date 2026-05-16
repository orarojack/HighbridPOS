// lib/features/pos/receipt.dart
//
// TEMPORARY STUB created during Task 13 so sale_screen.dart's `receipt.dart`
// import resolves. The real receipt widget + PDF builder is implemented in
// Task 14, which REPLACES this file entirely.
import 'package:flutter/material.dart';

import '../../domain/models.dart';

/// Temporary stub: shows a minimal confirmation that a sale completed.
/// Replaced by the full on-screen receipt + PDF export in Task 14.
Future<void> showReceiptDialog(BuildContext context, SaleRecord sale) {
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Sale complete'),
      content: const Text('Receipt printing is implemented in Task 14.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
