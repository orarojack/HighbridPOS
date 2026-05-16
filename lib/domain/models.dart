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
  final bool forcePinChange;

  const AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.active,
    this.forcePinChange = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppUser &&
          id == other.id &&
          username == other.username &&
          fullName == other.fullName &&
          role == other.role &&
          active == other.active &&
          forcePinChange == other.forcePinChange);

  @override
  int get hashCode =>
      Object.hash(id, username, fullName, role, active, forcePinChange);
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
/// [discount] is a fixed cent amount applied to the line; tax is computed on
/// the discounted (net) amount.
class CartLine {
  final Product product;
  final int qty;
  final int discount;

  const CartLine({
    required this.product,
    required this.qty,
    this.discount = 0,
  });

  int get unitPrice => product.sellPrice;
  int get lineSubtotal => unitPrice * qty;
  int get lineDiscount => discount.clamp(0, lineSubtotal);
  int get lineNet => lineSubtotal - lineDiscount;
  int get lineTax => (lineNet * product.taxRate).round();
  int get lineTotal => lineNet + lineTax;

  CartLine copyWith({int? qty, int? discount}) => CartLine(
        product: product,
        qty: qty ?? this.qty,
        discount: discount ?? this.discount,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CartLine &&
          product == other.product &&
          qty == other.qty &&
          discount == other.discount);

  @override
  int get hashCode => Object.hash(product, qty, discount);
}

/// Aggregated totals for a set of cart lines.
class CartTotals {
  final int subtotal;
  final int discountTotal;
  final int taxTotal;
  final int total;

  const CartTotals({
    required this.subtotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.total,
  });

  static const empty =
      CartTotals(subtotal: 0, discountTotal: 0, taxTotal: 0, total: 0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CartTotals &&
          subtotal == other.subtotal &&
          discountTotal == other.discountTotal &&
          taxTotal == other.taxTotal &&
          total == other.total);

  @override
  int get hashCode => Object.hash(subtotal, discountTotal, taxTotal, total);
}

/// A persisted sale line, snapshotting price/name at sale time.
/// [discount] is the line's total discount (cents) applied before tax.
class SaleLine {
  final String nameSnapshot;
  final int unitPrice;
  final double taxRate;
  final int qty;
  final int discount;
  final int lineTax;
  final int lineTotal;

  const SaleLine({
    required this.nameSnapshot,
    required this.unitPrice,
    required this.taxRate,
    required this.qty,
    this.discount = 0,
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
          discount == other.discount &&
          lineTax == other.lineTax &&
          lineTotal == other.lineTotal);

  @override
  int get hashCode => Object.hash(
      nameSnapshot, unitPrice, taxRate, qty, discount, lineTax, lineTotal);
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

/// A cashier shift record.
class Shift {
  final int id;
  final int userId;
  final String terminalId;
  final int openingFloat; // cents
  final ShiftStatus status;
  final DateTime openedAt;
  final DateTime? closedAt;
  final int cashSalesTotal; // cents
  final int payInTotal; // cents
  final int payOutTotal; // cents
  final int refundTotal; // cents — cash refunded out of the drawer
  final int? expectedCash; // cents
  final int? countedCash; // cents
  final int? variance; // cents
  final int? closedBy;
  final String note;

  const Shift({
    required this.id,
    required this.userId,
    required this.terminalId,
    required this.openingFloat,
    required this.status,
    required this.openedAt,
    required this.closedAt,
    required this.cashSalesTotal,
    required this.payInTotal,
    required this.payOutTotal,
    required this.refundTotal,
    required this.expectedCash,
    required this.countedCash,
    required this.variance,
    required this.closedBy,
    required this.note,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Shift &&
          id == other.id &&
          userId == other.userId &&
          terminalId == other.terminalId &&
          openingFloat == other.openingFloat &&
          status == other.status &&
          openedAt == other.openedAt &&
          closedAt == other.closedAt &&
          cashSalesTotal == other.cashSalesTotal &&
          payInTotal == other.payInTotal &&
          payOutTotal == other.payOutTotal &&
          refundTotal == other.refundTotal &&
          expectedCash == other.expectedCash &&
          countedCash == other.countedCash &&
          variance == other.variance &&
          closedBy == other.closedBy &&
          note == other.note);

  @override
  int get hashCode => Object.hash(
        id,
        userId,
        terminalId,
        openingFloat,
        status,
        openedAt,
        closedAt,
        cashSalesTotal,
        payInTotal,
        payOutTotal,
        refundTotal,
        expectedCash,
        countedCash,
        variance,
        closedBy,
        note,
      );
}

/// A single cash-drawer event within a shift.
class CashEvent {
  final int id;
  final int shiftId;
  final int userId;
  final CashEventType type;
  final int? amount; // cents; null for no-sale events
  final String reason;
  final int? approvedBy;
  final DateTime createdAt;

  const CashEvent({
    required this.id,
    required this.shiftId,
    required this.userId,
    required this.type,
    required this.amount,
    required this.reason,
    required this.approvedBy,
    required this.createdAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CashEvent &&
          id == other.id &&
          shiftId == other.shiftId &&
          userId == other.userId &&
          type == other.type &&
          amount == other.amount &&
          reason == other.reason &&
          approvedBy == other.approvedBy &&
          createdAt == other.createdAt);

  @override
  int get hashCode => Object.hash(
        id,
        shiftId,
        userId,
        type,
        amount,
        reason,
        approvedBy,
        createdAt,
      );
}

/// Aggregated view of a shift plus cashier name and event count.
class ShiftSummary {
  final Shift shift;
  final String cashierName;
  final int eventCount;

  const ShiftSummary({
    required this.shift,
    required this.cashierName,
    required this.eventCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShiftSummary &&
          shift == other.shift &&
          cashierName == other.cashierName &&
          eventCount == other.eventCount);

  @override
  int get hashCode => Object.hash(shift, cashierName, eventCount);
}

/// One product line in a return draft, built from a persisted sale item.
///
/// [saleItemDiscount] is the original sale_item's *total* discount, spread
/// across its [soldQty] units. Returning [selectedQty] units refunds the
/// proportional share of that discount (see [lineDiscount]).
class ReturnLineDraft {
  final int saleItemId;
  final int productId;
  final String nameSnapshot;
  final int unitPrice; // cents
  final double taxRate;
  final int soldQty;
  final int alreadyReturnedQty;
  final int selectedQty;
  final int saleItemDiscount; // cents — total discount on the original line

  ReturnLineDraft({
    required this.saleItemId,
    required this.productId,
    required this.nameSnapshot,
    required this.unitPrice,
    required this.taxRate,
    required this.soldQty,
    required this.alreadyReturnedQty,
    required this.selectedQty,
    this.saleItemDiscount = 0,
  });

  int get returnableQty => soldQty - alreadyReturnedQty;
  int get lineSubtotal => unitPrice * selectedQty;

  /// Proportional share of the original line discount for [selectedQty] units.
  int get lineDiscount =>
      soldQty == 0 ? 0 : (saleItemDiscount * selectedQty / soldQty).round();
  int get lineNet => lineSubtotal - lineDiscount;
  int get lineTax => (lineNet * taxRate).round();
  int get lineTotal => lineNet + lineTax;

  ReturnLineDraft copyWith({int? selectedQty}) => ReturnLineDraft(
        saleItemId: saleItemId,
        productId: productId,
        nameSnapshot: nameSnapshot,
        unitPrice: unitPrice,
        taxRate: taxRate,
        soldQty: soldQty,
        alreadyReturnedQty: alreadyReturnedQty,
        selectedQty: selectedQty ?? this.selectedQty,
        saleItemDiscount: saleItemDiscount,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReturnLineDraft &&
          saleItemId == other.saleItemId &&
          productId == other.productId &&
          nameSnapshot == other.nameSnapshot &&
          unitPrice == other.unitPrice &&
          taxRate == other.taxRate &&
          soldQty == other.soldQty &&
          alreadyReturnedQty == other.alreadyReturnedQty &&
          selectedQty == other.selectedQty &&
          saleItemDiscount == other.saleItemDiscount);

  @override
  int get hashCode => Object.hash(
        saleItemId,
        productId,
        nameSnapshot,
        unitPrice,
        taxRate,
        soldQty,
        alreadyReturnedQty,
        selectedQty,
        saleItemDiscount,
      );
}

/// In-memory return draft before it is persisted.
class ReturnDraft {
  final int originalSaleId;
  final String originalReference;
  final List<ReturnLineDraft> lines;
  final String reason;

  ReturnDraft({
    required this.originalSaleId,
    required this.originalReference,
    required List<ReturnLineDraft> lines,
    required this.reason,
  }) : lines = List.unmodifiable(lines);

  int get refundTotal => lines.fold(0, (sum, l) => sum + l.lineTotal);
  bool get hasSelection => lines.any((l) => l.selectedQty > 0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReturnDraft &&
          originalSaleId == other.originalSaleId &&
          originalReference == other.originalReference &&
          _listEquals(lines, other.lines) &&
          reason == other.reason);

  @override
  int get hashCode => Object.hash(
        originalSaleId,
        originalReference,
        Object.hashAll(lines),
        reason,
      );
}

/// A persisted return line, snapshotting quantities and amounts at return time.
/// [discount] is the proportional share of the original line discount that was
/// refunded for this return's [qty] units.
class ReturnLine {
  final int id;
  final int returnId;
  final int saleItemId;
  final int productId;
  final String nameSnapshot;
  final int qty;
  final int unitPrice; // cents
  final double taxRate;
  final int discount;
  final int lineTax;
  final int lineTotal;

  const ReturnLine({
    required this.id,
    required this.returnId,
    required this.saleItemId,
    required this.productId,
    required this.nameSnapshot,
    required this.qty,
    required this.unitPrice,
    required this.taxRate,
    this.discount = 0,
    required this.lineTax,
    required this.lineTotal,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReturnLine &&
          id == other.id &&
          returnId == other.returnId &&
          saleItemId == other.saleItemId &&
          productId == other.productId &&
          nameSnapshot == other.nameSnapshot &&
          qty == other.qty &&
          unitPrice == other.unitPrice &&
          taxRate == other.taxRate &&
          discount == other.discount &&
          lineTax == other.lineTax &&
          lineTotal == other.lineTotal);

  @override
  int get hashCode => Object.hash(
        id,
        returnId,
        saleItemId,
        productId,
        nameSnapshot,
        qty,
        unitPrice,
        taxRate,
        discount,
        lineTax,
        lineTotal,
      );
}

/// A completed return record read back from the database.
class ReturnRecord {
  final int id;
  final String referenceNo;
  final int originalSaleId;
  final String originalReference;
  final int cashierId;
  final int? shiftId;
  final String reason;
  final int refundTotal;
  final int? approvedBy;
  final DateTime createdAt;
  final List<ReturnLine> lines;

  ReturnRecord({
    required this.id,
    required this.referenceNo,
    required this.originalSaleId,
    required this.originalReference,
    required this.cashierId,
    required this.shiftId,
    required this.reason,
    required this.refundTotal,
    required this.approvedBy,
    required this.createdAt,
    required List<ReturnLine> lines,
  }) : lines = List.unmodifiable(lines);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReturnRecord &&
          id == other.id &&
          referenceNo == other.referenceNo &&
          originalSaleId == other.originalSaleId &&
          originalReference == other.originalReference &&
          cashierId == other.cashierId &&
          shiftId == other.shiftId &&
          reason == other.reason &&
          refundTotal == other.refundTotal &&
          approvedBy == other.approvedBy &&
          createdAt == other.createdAt &&
          _listEquals(lines, other.lines));

  @override
  int get hashCode => Object.hash(
        id,
        referenceNo,
        originalSaleId,
        originalReference,
        cashierId,
        shiftId,
        reason,
        refundTotal,
        approvedBy,
        createdAt,
        Object.hashAll(lines),
      );
}

/// Daily aggregate for the summary screen. The sale fields
/// ([subtotal]/[taxTotal]/[total]) keep their sale meaning; refunds are
/// reported separately via [returnCount] and [refundTotal].
class DailySummary {
  final DateTime day;
  final int saleCount;
  final int subtotal;
  final int discountTotal; // cents — sum of discounts applied across all sales
  final int taxTotal;
  final int total;
  final int returnCount;
  final int refundTotal; // cents — sum of refunds for the day

  const DailySummary({
    required this.day,
    required this.saleCount,
    required this.subtotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.total,
    required this.returnCount,
    required this.refundTotal,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailySummary &&
          day == other.day &&
          saleCount == other.saleCount &&
          subtotal == other.subtotal &&
          discountTotal == other.discountTotal &&
          taxTotal == other.taxTotal &&
          total == other.total &&
          returnCount == other.returnCount &&
          refundTotal == other.refundTotal);

  @override
  int get hashCode => Object.hash(
      day, saleCount, subtotal, discountTotal, taxTotal, total, returnCount, refundTotal);
}
