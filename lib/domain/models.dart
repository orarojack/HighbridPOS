// lib/domain/models.dart
import 'enums.dart';

/// Private helper: structural equality for two lists.
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppUser &&
          id == other.id &&
          username == other.username &&
          fullName == other.fullName &&
          role == other.role &&
          active == other.active);

  @override
  int get hashCode => Object.hash(id, username, fullName, role, active);
}

class Category {
  final int id;
  final String name;

  const Category({required this.id, required this.name});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category && id == other.id && name == other.name);

  @override
  int get hashCode => Object.hash(id, name);
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Product &&
          id == other.id &&
          sku == other.sku &&
          barcode == other.barcode &&
          name == other.name &&
          description == other.description &&
          categoryId == other.categoryId &&
          costPrice == other.costPrice &&
          sellPrice == other.sellPrice &&
          taxRate == other.taxRate &&
          stockQty == other.stockQty &&
          reorderLevel == other.reorderLevel &&
          active == other.active);

  @override
  int get hashCode => Object.hash(id, sku, barcode, name, description,
      categoryId, costPrice, sellPrice, taxRate, stockQty, reorderLevel, active);
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CartLine && product == other.product && qty == other.qty);

  @override
  int get hashCode => Object.hash(product, qty);
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CartTotals &&
          subtotal == other.subtotal &&
          taxTotal == other.taxTotal &&
          total == other.total);

  @override
  int get hashCode => Object.hash(subtotal, taxTotal, total);
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SaleLine &&
          nameSnapshot == other.nameSnapshot &&
          unitPrice == other.unitPrice &&
          taxRate == other.taxRate &&
          qty == other.qty &&
          lineTax == other.lineTax &&
          lineTotal == other.lineTotal);

  @override
  int get hashCode =>
      Object.hash(nameSnapshot, unitPrice, taxRate, qty, lineTax, lineTotal);
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

  SaleRecord({
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
    required List<SaleLine> lines,
  }) : lines = List.unmodifiable(lines);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SaleRecord &&
          id == other.id &&
          referenceNo == other.referenceNo &&
          cashierId == other.cashierId &&
          cashierName == other.cashierName &&
          subtotal == other.subtotal &&
          taxTotal == other.taxTotal &&
          total == other.total &&
          tendered == other.tendered &&
          changeDue == other.changeDue &&
          createdAt == other.createdAt &&
          _listEquals(lines, other.lines));

  @override
  int get hashCode => Object.hash(
        id,
        referenceNo,
        cashierId,
        cashierName,
        subtotal,
        taxTotal,
        total,
        tendered,
        changeDue,
        createdAt,
        Object.hashAll(lines),
      );
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailySummary &&
          day == other.day &&
          saleCount == other.saleCount &&
          subtotal == other.subtotal &&
          taxTotal == other.taxTotal &&
          total == other.total);

  @override
  int get hashCode => Object.hash(day, saleCount, subtotal, taxTotal, total);
}
