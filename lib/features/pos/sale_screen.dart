// lib/features/pos/sale_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/sale_repository.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../../shared/money.dart';
import '../auth/auth_controller.dart';
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

  Future<void> _checkout() async {
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
            lines: cart,
            tendered: tendered,
          );
      ref.read(cartControllerProvider.notifier).clear();
      await _runSearch(_searchController.text);
      if (mounted) await showReceiptDialog(context, sale);
    } on InsufficientStockException catch (e) {
      _snack('Sale failed: ${e.productName} ran out of stock.');
    } catch (e) {
      _snack('Sale failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text('Current sale',
                          style: Theme.of(context).textTheme.titleLarge),
                      const Spacer(),
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
                      onPressed: cart.isEmpty ? null : _checkout,
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
