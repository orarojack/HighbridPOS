// lib/features/returns/return_receipt.dart
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/models.dart';
import '../../shared/money.dart';
import '../../shared/theme.dart';

/// Builds a printable PDF receipt for a recorded return / cash refund.
Future<pw.Document> buildReturnReceiptPdf(ReturnRecord record) async {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text('HighbridPOS',
                style: pw.TextStyle(
                    fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text('RETURN / REFUND',
                style: pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Return ${record.referenceNo}'),
          pw.Text('Original sale #${record.originalSaleId}'),
          pw.Text(formatDateTime(record.createdAt)),
          if (record.reason.isNotEmpty) pw.Text('Reason: ${record.reason}'),
          pw.Divider(),
          for (final line in record.lines)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                    child: pw.Text('${line.qty} x ${line.nameSnapshot}')),
                pw.Text(formatMoney(line.lineTotal)),
              ],
            ),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Refund total',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(formatMoney(record.refundTotal),
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Center(child: pw.Text('Refund paid in cash')),
        ],
      ),
    ),
  );
  return doc;
}

/// Shows the on-screen return receipt with an option to export/print the PDF.
Future<void> showReturnReceiptDialog(
    BuildContext context, ReturnRecord record) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Return ${record.referenceNo}'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text('RETURN / REFUND',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 4),
            Text('Original sale #${record.originalSaleId}'),
            Text(formatDateTime(record.createdAt)),
            if (record.reason.isNotEmpty) Text('Reason: ${record.reason}'),
            const Divider(),
            for (final line in record.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child:
                            Text('${line.qty} x ${line.nameSnapshot}')),
                    Text(formatMoney(line.lineTotal)),
                  ],
                ),
              ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Refund total',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(formatMoney(record.refundTotal),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Print / PDF'),
          onPressed: () async {
            final doc = await buildReturnReceiptPdf(record);
            await Printing.layoutPdf(onLayout: (_) => doc.save());
          },
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
