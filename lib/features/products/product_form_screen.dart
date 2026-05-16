// lib/features/products/product_form_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../providers.dart';
import '../../shared/money.dart';
import 'product_controller.dart';

/// Add or edit a product. Pass [existing] to edit; null to create.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.existing});
  final Product? existing;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _cost;
  late final TextEditingController _sell;
  late final TextEditingController _tax;
  late final TextEditingController _stock;
  late final TextEditingController _reorder;
  int? _categoryId;
  late bool _active;
  String? _error;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _sku = TextEditingController(text: e?.sku ?? '');
    _barcode = TextEditingController(text: e?.barcode ?? '');
    _name = TextEditingController(text: e?.name ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _cost = TextEditingController(text: e == null ? '' : formatMoney(e.costPrice));
    _sell = TextEditingController(text: e == null ? '' : formatMoney(e.sellPrice));
    _tax = TextEditingController(
        text: e == null ? '0' : (e.taxRate * 100).toStringAsFixed(0));
    _stock = TextEditingController(text: e == null ? '0' : e.stockQty.toString());
    _reorder =
        TextEditingController(text: e == null ? '0' : e.reorderLevel.toString());
    _categoryId = e?.categoryId;
    _active = e?.active ?? true;
  }

  @override
  void dispose() {
    for (final c in [
      _sku, _barcode, _name, _description, _cost, _sell, _tax, _stock, _reorder
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(productRepositoryProvider);
    final barcode = _barcode.text.trim().isEmpty ? null : _barcode.text.trim();
    final taxRate = (double.tryParse(_tax.text.trim()) ?? 0) / 100;
    try {
      if (_isEdit) {
        await repo.update(
          widget.existing!.id,
          sku: _sku.text.trim(),
          barcode: barcode,
          name: _name.text.trim(),
          description: _description.text.trim(),
          categoryId: _categoryId,
          costPrice: parseMoney(_cost.text) ?? 0,
          sellPrice: parseMoney(_sell.text)!,
          taxRate: taxRate,
          reorderLevel: int.tryParse(_reorder.text.trim()) ?? 0,
          active: _active,
        );
      } else {
        await repo.create(
          sku: _sku.text.trim(),
          barcode: barcode,
          name: _name.text.trim(),
          description: _description.text.trim(),
          categoryId: _categoryId,
          costPrice: parseMoney(_cost.text) ?? 0,
          sellPrice: parseMoney(_sell.text)!,
          taxRate: taxRate,
          stockQty: int.tryParse(_stock.text.trim()) ?? 0,
          reorderLevel: int.tryParse(_reorder.text.trim()) ?? 0,
        );
      }
      ref.invalidate(productListProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Could not save — SKU or barcode may already be in use.';
      });
    }
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _money(String? v) =>
      parseMoney(v ?? '') == null ? 'Enter a valid amount' : null;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit product' : 'New product')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Product name'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _sku,
                  decoration: const InputDecoration(labelText: 'SKU'),
                  validator: _required,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _barcode,
                  decoration:
                      const InputDecoration(labelText: 'Barcode (optional)'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            categories.when(
              data: (list) => DropdownButtonFormField<int?>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  for (final c in list)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Could not load categories'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _cost,
                  decoration: const InputDecoration(labelText: 'Cost price'),
                  validator: _money,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _sell,
                  decoration: const InputDecoration(labelText: 'Selling price'),
                  validator: _money,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _tax,
                  decoration: const InputDecoration(labelText: 'Tax %'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _stock,
                  decoration: InputDecoration(
                    labelText: 'Stock quantity',
                    helperText: _isEdit ? 'Adjust stock in a later release' : null,
                  ),
                  enabled: !_isEdit,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _reorder,
                  decoration: const InputDecoration(labelText: 'Reorder level'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ]),
            if (_isEdit) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('Active'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_isEdit ? 'Save changes' : 'Create product'),
            ),
          ],
        ),
      ),
    );
  }
}
