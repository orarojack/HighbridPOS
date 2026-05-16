// lib/features/products/product_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../providers.dart';

/// Loads all products (active and inactive) for the management list.
final productListProvider = FutureProvider.autoDispose<List<Product>>(
  (ref) => ref.watch(productRepositoryProvider).allProducts(),
);

final categoriesProvider = FutureProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(productRepositoryProvider).allCategories(),
);
