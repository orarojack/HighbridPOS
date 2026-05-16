// lib/features/pos/sale_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/sale_repository.dart';
import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../../shared/manager_approval.dart';
import '../../shared/money.dart';
import '../auth/auth_controller.dart';
import '../shift/shift_controller.dart';
import '../shift/start_shift_screen.dart';
import 'cart_controller.dart';
import 'payment_dialog.dart';
import 'receipt.dart';

class SaleScreen extends ConsumerStatefulWidget {
  const SaleScreen({super.key});

  @override
  ConsumerState<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends ConsumerState<SaleScreen> {
  final _searchController = TextEditingController();
  List<Product> _results = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _runSearch('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String term) async {
    setState(() => _searching = true);
    final results =
        await ref.read(productRepositoryProvider).search(term);
    if (mounted) {
      setState(() {
        _results = results;
        _searching = false;
      });
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _add(Product product) {
    final ok = ref.read(cartControllerProvider.notifier).addProduct(product);
    if (!ok) _snack('Not enough stock for ${product.name}.');
  }

  Future<void> _checkout(Shift shift) async {
    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty) {
      _snack('The cart is empty.');
      return;
    }
    final totals = ref.read(cartControllerProvider.notifier).totals;
    final tendered = await PaymentDialog.show(context, totals.total);
    if (tendered == null) return;

    final cashier = ref.read(authControllerProvider)!;
    try {
      final sale = await ref.read(saleRepositoryProvider).completeCashSale(
            cashierId: cashier.id,
            shiftId: shift.id,
            lines: cart,
            tendered: tendered,
          );
      ref.read(cartControllerProvider.notifier).clear();
      await _runSearch(_searchController.text);
      // Refresh the shift so its running cash total stays current.
      await ref.read(shiftControllerProvider.notifier).refresh();
      if (mounted) await showReceiptDialog(context, sale);
    } on InsufficientStockException catch (e) {
      _snack('Sale failed: ${e.productName} ran out of stock.');
    } catch (e) {
      _snack('Sale failed: $e');
    }
  }

  /// Records a no-sale drawer open against [shift] after a manager approves.
  Future<void> _noSale(Shift shift) async {
    final approver = await requestManagerApproval(
      context,
      ref,
      action: 'Open the cash drawer (no sale)',
    );
    if (approver == null) return;
    final cashier = ref.read(authControllerProvider)!;
    try {
      await ref.read(shiftRepositoryProvider).recordNoSale(
            shiftId: shift.id,
            userId: cashier.id,
            approvedBy: approver.id,
            reason: 'No-sale drawer open',
          );
      _snack('Drawer opened — no sale recorded.');
    } catch (e) {
      _snack('Could not record the no-sale: $e');
    }
  }

  /// Records a pay-in or pay-out cash movement against [shift]. Prompts the
  /// cashier for an amount and reason via [CashMovementDialog]. No manager
  /// approval is required for routine cash movements.
  Future<void> _cashMovement(Shift shift, CashEventType type) async {
    final result = await CashMovementDialog.show(context, type);
    if (result == null) return;
    final cashier = ref.read(authControllerProvider)!;
    try {
      await ref.read(shiftRepositoryProvider).addCashMovement(
            shiftId: shift.id,
            userId: cashier.id,
            type: type,
            amount: result.amount,
            reason: result.reason,
          );
      // Refresh the shift so the end-shift expected-cash stays accurate.
      await ref.read(shiftControllerProvider.notifier).refresh();
      if (!mounted) return;
      final label = type == CashEventType.payIn ? 'in' : 'out';
      _snack('Cash $label of ${formatMoney(result.amount)} recorded.');
    } catch (e) {
      if (mounted) _snack('Could not record the cash movement: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final shiftState = ref.watch(shiftControllerProvider);

    return shiftState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Could not load the shift: $e')),
      ),
      data: (shift) => shift == null
          ? const _ShiftGate()
          : _buildSaleUi(context, shift),
    );
  }

  Widget _buildSaleUi(BuildContext context, Shift shift) {
    final cart = ref.watch(cartControllerProvider);
    final totals = ref.watch(cartControllerProvider.notifier).totals;

    return Scaffold(
      body: Row(
        children: [
          // Product search + results.
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Scan barcode or search products',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            )
                          : null,
                    ),
                    onChanged: _runSearch,
                    onSubmitted: (term) {
                      if (_results.length == 1) {
                        _add(_results.first);
                        _searchController.clear();
                        _runSearch('');
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _results.isEmpty
                        ? const Center(child: Text('No matching products.'))
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              childAspectRatio: 1.6,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemCount: _results.length,
                            itemBuilder: (context, i) {
                              final p = _results[i];
                              return Card(
                                child: InkWell(
                                  onTap: () => _add(p),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(p.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold)),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                  formatMoney(p.sellPrice),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  softWrap: false),
                                            ),
                                            Flexible(
                                              child: Text('Stock ${p.stockQty}',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  softWrap: false,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          // Cart.
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Current sale',
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.titleLarge),
                      ),
                      if (cart.isNotEmpty)
                        TextButton(
                          onPressed: () => ref
                              .read(cartControllerProvider.notifier)
                              .clear(),
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: () => _noSale(shift),
                          icon: const Icon(Icons.lock_open),
                          label: const Text('No-sale (open drawer)'),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              _cashMovement(shift, CashEventType.payIn),
                          icon: const Icon(Icons.add),
                          label: const Text('Cash in'),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              _cashMovement(shift, CashEventType.payOut),
                          icon: const Icon(Icons.remove),
                          label: const Text('Cash out'),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: cart.isEmpty
                      ? const Center(child: Text('Cart is empty.'))
                      : ListView.builder(
                          itemCount: cart.length,
                          itemBuilder: (context, i) =>
                              _CartTile(line: cart[i]),
                        ),
                ),
                const Divider(height: 1),
                _TotalsPanel(
                  subtotal: totals.subtotal,
                  taxTotal: totals.taxTotal,
                  total: totals.total,
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: cart.isEmpty ? null : () => _checkout(shift),
                      icon: const Icon(Icons.payments),
                      label: const Text('Take cash payment'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The result of a confirmed [CashMovementDialog]: a parsed [amount] in cents
/// and the cashier-supplied [reason].
class CashMovementResult {
  const CashMovementResult({required this.amount, required this.reason});
  final int amount;
  final String reason;
}

/// Small dialog that collects an amount and a reason for a pay-in / pay-out
/// cash movement. Resolves to a [CashMovementResult], or null if cancelled.
class CashMovementDialog extends StatefulWidget {
  const CashMovementDialog({super.key, required this.type});
  final CashEventType type;

  static Future<CashMovementResult?> show(
          BuildContext context, CashEventType type) =>
      showDialog<CashMovementResult>(
        context: context,
        builder: (_) => CashMovementDialog(type: type),
      );

  @override
  State<CashMovementDialog> createState() => _CashMovementDialogState();
}

class _CashMovementDialogState extends State<CashMovementDialog> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPayIn = widget.type == CashEventType.payIn;
    final amount = parseMoney(_amount.text);
    final reason = _reason.text.trim();
    final valid = amount != null && amount > 0 && reason.isNotEmpty;

    return AlertDialog(
      title: Text(isPayIn ? 'Cash in' : 'Cash out'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Reason'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.of(context).pop(
                    CashMovementResult(amount: amount, reason: reason),
                  )
              : null,
          child: Text(isPayIn ? 'Record cash in' : 'Record cash out'),
        ),
      ],
    );
  }
}

/// Shown in place of the sale UI when the signed-in user has no open shift.
class _ShiftGate extends StatelessWidget {
  const _ShiftGate();

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
                  Icon(Icons.point_of_sale,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('Start your shift to begin selling',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Selling is locked until a shift is open on this terminal.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start shift'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => StartShiftScreen(
                            onStarted: () => Navigator.of(context).pop(),
                          ),
                        ),
                      );
                    },
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

class _CartTile extends ConsumerWidget {
  const _CartTile({required this.line});
  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(cartControllerProvider.notifier);
    return ListTile(
      title: Text(line.product.name),
      subtitle: Text('${formatMoney(line.unitPrice)} each'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () =>
                controller.setQty(line.product.id, line.qty - 1),
          ),
          Text('${line.qty}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () {
              final ok =
                  controller.setQty(line.product.id, line.qty + 1);
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        'Not enough stock for ${line.product.name}.')));
              }
            },
          ),
          SizedBox(
            width: 80,
            child: Text(formatMoney(line.lineTotal),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _TotalsPanel extends StatelessWidget {
  const _TotalsPanel({
    required this.subtotal,
    required this.taxTotal,
    required this.total,
  });
  final int subtotal;
  final int taxTotal;
  final int total;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, int value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      fontWeight:
                          bold ? FontWeight.bold : FontWeight.normal)),
              Text(formatMoney(value),
                  style: TextStyle(
                      fontSize: bold ? 18 : 14,
                      fontWeight:
                          bold ? FontWeight.bold : FontWeight.normal)),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          row('Subtotal', subtotal),
          row('Tax', taxTotal),
          row('Total', total, bold: true),
        ],
      ),
    );
  }
}
