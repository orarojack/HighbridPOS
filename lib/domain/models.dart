// lib/domain/models.dart
import 'enums.dart';

class AppUser {
  final int id;
  final String username;
  final String fullName;
  final UserRole role;
  final bool active;

  const AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.active,
  });
}

class Category {
  final int id;
  final String name;

  const Category({required this.id, required this.name});
}

class Product {
  final int id;
  final String sku;
  final String? barcode;
  final String name;
  final String description;
  final int? categoryId;
  final int costPrice; // cents
  final int sellPrice; // cents
  final double taxRate; // e.g. 0.16 for 16%
  final int stockQty;
  final int reorderLevel;
  final bool active;

  const Product({
    required this.id,
    required this.sku,
    required this.barcode,
    required this.name,
    required this.description,
    required this.categoryId,
    required this.costPrice,
    required this.sellPrice,
    required this.taxRate,
    required this.stockQty,
    required this.reorderLevel,
    required this.active,
  });
}

/// One product line in the in-memory cart. [qty] > 0.
class CartLine {
  final Product product;
  final int qty;

  const CartLine({required this.product, required this.qty});

  int get unitPrice => product.sellPrice;
  int get lineSubtotal => unitPrice * qty;
  int get lineTax => (lineSubtotal * product.taxRate).round();
  int get lineTotal => lineSubtotal + lineTax;

  CartLine copyWith({int? qty}) =>
      CartLine(product: product, qty: qty ?? this.qty);
}

/// Aggregated totals for a set of cart lines.
class CartTotals {
  final int subtotal;
  final int taxTotal;
  final int total;

  const CartTotals({
    required this.subtotal,
    required this.taxTotal,
    required this.total,
  });

  static const empty = CartTotals(subtotal: 0, taxTotal: 0, total: 0);
}

/// A persisted sale line, snapshotting price/name at sale time.
class SaleLine {
  final String nameSnapshot;
  final int unitPrice;
  final double taxRate;
  final int qty;
  final int lineTax;
  final int lineTotal;

  const SaleLine({
    required this.nameSnapshot,
    required this.unitPrice,
    required this.taxRate,
    required this.qty,
    required this.lineTax,
    required this.lineTotal,
  });
}

/// A completed sale read back from the database.
class SaleRecord {
  final int id;
  final String referenceNo;
  final int cashierId;
  final String cashierName;
  final int subtotal;
  final int taxTotal;
  final int total;
  final int tendered;
  final int changeDue;
  final DateTime createdAt;
  final List<SaleLine> lines;

  const SaleRecord({
    required this.id,
    required this.referenceNo,
    required this.cashierId,
    required this.cashierName,
    required this.subtotal,
    required this.taxTotal,
    required this.total,
    required this.tendered,
    required this.changeDue,
    required this.createdAt,
    required this.lines,
  });
}

/// Daily aggregate for the summary screen.
class DailySummary {
  final DateTime day;
  final int saleCount;
  final int subtotal;
  final int taxTotal;
  final int total;

  const DailySummary({
    required this.day,
    required this.saleCount,
    required this.subtotal,
    required this.taxTotal,
    required this.total,
  });
}
