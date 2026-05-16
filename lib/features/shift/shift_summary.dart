// lib/features/shift/shift_summary.dart
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/models.dart';
import '../../shared/money.dart';
import '../../shared/theme.dart';

/// On-screen summary of a closed (or open) shift: floats, cash sales, pay
/// movements, expected/counted cash, variance, cashier and times.
class ShiftSummaryView extends StatelessWidget {
  const ShiftSummaryView({super.key, required this.summary});

  final ShiftSummary summary;

  @override
  Widget build(BuildContext context) {
    final shift = summary.shift;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Shift summary',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Cashier: ${summary.cashierName}',
                style: Theme.of(context).textTheme.bodySmall),
            Text('Terminal: ${shift.terminalId}',
                style: Theme.of(context).textTheme.bodySmall),
            const Divider(height: 24),
            _SummaryRow(label: 'Opening float', value: shift.openingFloat),
            _SummaryRow(label: 'Cash sales', value: shift.cashSalesTotal),
            _SummaryRow(label: 'Pay-in', value: shift.payInTotal),
            _SummaryRow(label: 'Pay-out', value: shift.payOutTotal),
            const Divider(height: 24),
            if (shift.expectedCash != null)
              _SummaryRow(
                  label: 'Expected cash',
                  value: shift.expectedCash!,
                  bold: true),
            if (shift.countedCash != null)
              _SummaryRow(label: 'Counted cash', value: shift.countedCash!),
            if (shift.variance != null)
              _SummaryRow(
                  label: 'Variance', value: shift.variance!, bold: true),
            const Divider(height: 24),
            _TextRow(label: 'Opened', value: formatDateTime(shift.openedAt)),
            if (shift.closedAt != null)
              _TextRow(
                  label: 'Closed',
                  value: formatDateTime(shift.closedAt!)),
            _TextRow(label: 'Cash events', value: '${summary.eventCount}'),
            if (shift.note.isNotEmpty)
              _TextRow(label: 'Note', value: shift.note),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Print / PDF'),
                onPressed: () async {
                  final doc = await buildShiftSummaryPdf(summary);
                  await Printing.layoutPdf(onLayout: (_) => doc.save());
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(
      {required this.label, required this.value, this.bold = false});
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

class _TextRow extends StatelessWidget {
  const _TextRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Flexible(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

/// Builds a printable PDF of the shift summary. Pure builder, no side effects.
Future<pw.Document> buildShiftSummaryPdf(ShiftSummary summary) async {
  final shift = summary.shift;
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text('HighbridPOS — Shift Summary',
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Cashier: ${summary.cashierName}'),
          pw.Text('Terminal: ${shift.terminalId}'),
          pw.Text('Opened: ${formatDateTime(shift.openedAt)}'),
          if (shift.closedAt != null)
            pw.Text('Closed: ${formatDateTime(shift.closedAt!)}'),
          pw.Divider(),
          _pdfRow('Opening float', shift.openingFloat),
          _pdfRow('Cash sales', shift.cashSalesTotal),
          _pdfRow('Pay-in', shift.payInTotal),
          _pdfRow('Pay-out', shift.payOutTotal),
          pw.Divider(),
          if (shift.expectedCash != null)
            _pdfRow('Expected cash', shift.expectedCash!, bold: true),
          if (shift.countedCash != null)
            _pdfRow('Counted cash', shift.countedCash!),
          if (shift.variance != null)
            _pdfRow('Variance', shift.variance!, bold: true),
          if (shift.note.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text('Note: ${shift.note}'),
          ],
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
            style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
        pw.Text(formatMoney(value),
            style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
      ],
    );
