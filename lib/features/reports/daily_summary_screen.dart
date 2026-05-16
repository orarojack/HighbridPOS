// lib/features/reports/daily_summary_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../providers.dart';
import '../../shared/money.dart';
import '../../shared/theme.dart';

final _dailySummaryProvider = FutureProvider.autoDispose<DailySummary>(
  (ref) => ref.watch(reportRepositoryProvider).dailySummary(DateTime.now()),
);

class DailySummaryScreen extends ConsumerWidget {
  const DailySummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(_dailySummaryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_dailySummaryProvider),
          ),
        ],
      ),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load summary: $e')),
        data: (s) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(formatDay(s.day),
                        style: Theme.of(context).textTheme.titleMedium),
                    const Divider(height: 24),
                    _row('Sales completed', s.saleCount.toString()),
                    _row('Subtotal', formatMoney(s.subtotal)),
                    _row('Tax collected', formatMoney(s.taxTotal)),
                    const Divider(height: 24),
                    _row('Total takings', formatMoney(s.total), bold: true),
                    const Divider(height: 24),
                    _row('Returns processed', s.returnCount.toString()),
                    _row('Refunds issued', formatMoney(s.refundTotal)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight:
                        bold ? FontWeight.bold : FontWeight.normal)),
            Text(value,
                style: TextStyle(
                    fontSize: bold ? 20 : 14,
                    fontWeight:
                        bold ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      );
}
