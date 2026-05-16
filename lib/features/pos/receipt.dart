// lib/features/pos/receipt.dart
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/models.dart';
import '../../shared/money.dart';
import '../../shared/theme.dart';

/// Builds a printable PDF receipt for a completed sale.
Future<pw.Document> buildReceiptPdf(SaleRecord sale) async {
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
          pw.SizedBox(height: 4),
          pw.Text('Receipt ${sale.referenceNo}'),
          pw.Text(formatDateTime(sale.createdAt)),
          pw.Text('Cashier: ${sale.cashierName}'),
          pw.Divider(),
          for (final line in sale.lines)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                    child: pw.Text(
                        '${line.qty} x ${line.nameSnapshot}')),
                pw.Text(formatMoney(line.lineTotal)),
              ],
            ),
          pw.Divider(),
          _pdfRow('Subtotal', sale.subtotal),
          _pdfRow('Tax', sale.taxTotal),
          _pdfRow('Total', sale.total, bold: true),
          _pdfRow('Cash', sale.tendered),
          _pdfRow('Change', sale.changeDue),
          pw.SizedBox(height: 8),
          pw.Center(child: pw.Text('Thank you for shopping with us')),
        ],
      ),
    ),
  );
  return doc;
}

pw.Widget _pdfRow(String label, int value, {bool bold = false}) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label,
            style: bold
                ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                : null),
        pw.Text(formatMoney(value),
            style: bold
                ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                : null),
      ],
    );

/// Shows the on-screen receipt with an option to export/print the PDF.
Future<void> showReceiptDialog(BuildContext context, SaleRecord sale) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Sale ${sale.referenceNo}'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(formatDateTime(sale.createdAt)),
            Text('Cashier: ${sale.cashierName}'),
            const Divider(),
            for (final line in sale.lines)
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
            _ScreenRow(label: 'Subtotal', value: sale.subtotal),
            _ScreenRow(label: 'Tax', value: sale.taxTotal),
            _ScreenRow(label: 'Total', value: sale.total, bold: true),
            _ScreenRow(label: 'Cash', value: sale.tendered),
            _ScreenRow(label: 'Change', value: sale.changeDue, bold: true),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Print / PDF'),
          onPressed: () async {
            final doc = await buildReceiptPdf(sale);
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

class _ScreenRow extends StatelessWidget {
  const _ScreenRow(
      {required this.label, required this.value, this.bold = false});
  final String label;
  final int value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(formatMoney(value), style: style)],
      ),
    );
  }
}
