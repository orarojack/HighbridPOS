// lib/features/products/product_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/money.dart';
import 'product_controller.dart';
import 'product_form_screen.dart';

class ProductListScreen extends ConsumerWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ProductFormScreen(),
              )),
              icon: const Icon(Icons.add),
              label: const Text('New product'),
            ),
          ),
        ],
      ),
      body: products.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load products: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No products yet.'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = list[i];
              final lowStock = p.stockQty <= p.reorderLevel;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: p.active
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).disabledColor,
                  child: Text(p.name.isEmpty ? '?' : p.name[0]),
                ),
                title: Text(p.name),
                subtitle: Text('SKU ${p.sku}'
                    '${p.barcode != null ? '  ·  ${p.barcode}' : ''}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatMoney(p.sellPrice),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      'Stock ${p.stockQty}',
                      style: TextStyle(
                        color: lowStock
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                  ],
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ProductFormScreen(existing: p),
                )),
              );
            },
          );
        },
      ),
    );
  }
}
