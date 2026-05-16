// lib/providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/db/app_database.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/product_repository.dart';
import 'data/repositories/report_repository.dart';
import 'data/repositories/return_repository.dart';
import 'data/repositories/sale_repository.dart';
import 'data/repositories/shift_repository.dart';

/// Overridden in main() with the opened database instance.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(databaseProvider)),
);

final productRepositoryProvider = Provider<ProductRepository>(
  (ref) => ProductRepository(ref.watch(databaseProvider)),
);

final saleRepositoryProvider = Provider<SaleRepository>(
  (ref) => SaleRepository(ref.watch(databaseProvider)),
);

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ref.watch(databaseProvider)),
);

final shiftRepositoryProvider = Provider<ShiftRepository>(
  (ref) => ShiftRepository(ref.watch(databaseProvider)),
);

final returnRepositoryProvider = Provider<ReturnRepository>(
  (ref) => ReturnRepository(ref.watch(databaseProvider)),
);
