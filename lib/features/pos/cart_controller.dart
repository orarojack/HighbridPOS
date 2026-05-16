// lib/features/pos/cart_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../domain/sale_calculator.dart';

/// In-memory cart for the current sale. Cleared after a completed sale.
class CartController extends StateNotifier<List<CartLine>> {
  CartController() : super(const []);

  /// Adds one unit of [product]. Returns false if that would exceed stock.
  bool addProduct(Product product) {
    final idx = state.indexWhere((l) => l.product.id == product.id);
    if (idx == -1) {
      if (product.stockQty < 1) return false;
      state = [...state, CartLine(product: product, qty: 1)];
      return true;
    }
    final line = state[idx];
    if (line.qty + 1 > line.product.stockQty) return false;
    state = [
      for (var i = 0; i < state.length; i++)
        if (i == idx) line.copyWith(qty: line.qty + 1) else state[i],
    ];
    return true;
  }

  /// Sets an explicit quantity for a product. Removes the line if qty <= 0.
  /// Returns false if [qty] exceeds available stock.
  bool setQty(int productId, int qty) {
    final idx = state.indexWhere((l) => l.product.id == productId);
    if (idx == -1) return false;
    final line = state[idx];
    if (qty <= 0) {
      removeProduct(productId);
      return true;
    }
    if (qty > line.product.stockQty) return false;
    state = [
      for (var i = 0; i < state.length; i++)
        if (i == idx) line.copyWith(qty: qty) else state[i],
    ];
    return true;
  }

  void removeProduct(int productId) {
    state = state.where((l) => l.product.id != productId).toList();
  }

  void clear() => state = const [];

  CartTotals get totals => calculateTotals(state);
}

final cartControllerProvider =
    StateNotifierProvider<CartController, List<CartLine>>(
  (ref) => CartController(),
);
