# HighbridPOS Slice 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone Flutter desktop POS terminal — cashier login, product management, cash-sale checkout with stock deduction, receipts, and a daily sales summary — backed by a local SQLite database.

**Architecture:** Layered Flutter app. UI (screens) → Riverpod providers (state) → repositories (interfaces, the swap seam for a future backend) → drift SQLite data source. Pure-Dart domain logic for money and sale calculations, fully unit-tested. A completed sale writes sale/items/payment/stock-movement rows in one DB transaction.

**Tech Stack:** Flutter Desktop, drift (SQLite ORM), Riverpod, bcrypt, pdf + printing, build_runner.

---

## Prerequisite: Toolchain

The Flutter SDK (which bundles Dart) must be installed and on `PATH`, and Linux desktop
build support enabled. If `flutter --version` fails, install from
<https://docs.flutter.dev/get-started/install/linux/desktop> first, then run
`flutter config --enable-linux-desktop` and `flutter doctor`. Every `flutter`/`dart`
command in this plan assumes the SDK is available.

## File Structure

```
pubspec.yaml                              dependencies
lib/main.dart                             entry point — DB init + runApp
lib/app.dart                              MaterialApp, theme, routing
lib/shared/theme.dart                     app theme + money/date formatting
lib/shared/money.dart                     integer-cents money helpers
lib/domain/enums.dart                     UserRole, SaleStatus, PaymentMethod, MovementType
lib/domain/models.dart                    Product, Category, AppUser, CartLine, CartTotals,
                                          SaleRecord, SaleLine
lib/domain/sale_calculator.dart           pure sale-calculation functions
lib/data/db/app_database.dart             drift tables + AppDatabase
lib/data/db/seed.dart                     first-run seeding
lib/data/repositories/auth_repository.dart
lib/data/repositories/product_repository.dart
lib/data/repositories/sale_repository.dart
lib/data/repositories/report_repository.dart
lib/providers.dart                        database + repository Riverpod providers
lib/features/auth/auth_controller.dart    auth state (logged-in user)
lib/features/auth/login_screen.dart
lib/features/products/product_controller.dart
lib/features/products/product_list_screen.dart
lib/features/products/product_form_screen.dart
lib/features/pos/cart_controller.dart     in-memory cart state
lib/features/pos/sale_screen.dart
lib/features/pos/payment_dialog.dart
lib/features/pos/receipt.dart             receipt widget + PDF builder
lib/features/reports/daily_summary_screen.dart
test/sale_calculator_test.dart
test/money_test.dart
test/repositories_test.dart
test/login_screen_test.dart
test/sale_screen_test.dart
```

---

### Task 1: Scaffold the Flutter project

**Files:**
- Create: project skeleton via `flutter create`
- Modify: `pubspec.yaml`
- Create: `analysis_options.yaml` (from template, kept)

- [ ] **Step 1: Create the Flutter project in place**

The repo already contains `LICENSE`, `README.md`, `docs/`, `.git`. Generate the Flutter
project into the existing directory:

```bash
cd /home/oraro/HighbridPOS
flutter create --org com.caavagroup --project-name highbrid_pos --platforms=linux .
```

Expected: Flutter scaffolds `lib/`, `linux/`, `pubspec.yaml`, `test/` without deleting
`docs/`, `LICENSE`, or `README.md`.

- [ ] **Step 2: Replace `pubspec.yaml` dependencies**

Set the `dependencies` and `dev_dependencies` blocks (keep the existing `name`,
`description`, `version`, `environment`, and `flutter:` sections):

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  drift: ^2.18.0
  sqlite3_flutter_libs: ^0.5.24
  path_provider: ^2.1.3
  path: ^1.9.0
  bcrypt: ^1.1.3
  pdf: ^3.11.0
  printing: ^5.13.1
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  drift_dev: ^2.18.0
  build_runner: ^2.4.11
```

- [ ] **Step 3: Fetch packages**

Run: `flutter pub get`
Expected: `Got dependencies!` with no version-solve errors.

- [ ] **Step 4: Verify the scaffold builds**

Run: `flutter analyze`
Expected: `No issues found!` (the generated `widget_test.dart` may fail later — it is
replaced in Task 14; leaving it now is fine for analyze).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: scaffold Flutter desktop project with dependencies"
```

---

### Task 2: Money helpers

All monetary amounts are integer minor units (cents). This task adds formatting/parsing
helpers, test-driven.

**Files:**
- Create: `lib/shared/money.dart`
- Test: `test/money_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/money_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/shared/money.dart';

void main() {
  test('formatMoney renders cents as 2-decimal currency', () {
    expect(formatMoney(0), '0.00');
    expect(formatMoney(5), '0.05');
    expect(formatMoney(199), '1.99');
    expect(formatMoney(123456), '1234.56');
  });

  test('parseMoney converts a decimal string to cents', () {
    expect(parseMoney('0'), 0);
    expect(parseMoney('1.99'), 199);
    expect(parseMoney('1.5'), 150);
    expect(parseMoney('1234.56'), 123456);
  });

  test('parseMoney returns null for invalid input', () {
    expect(parseMoney(''), isNull);
    expect(parseMoney('abc'), isNull);
    expect(parseMoney('-5'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/money_test.dart`
Expected: FAIL — `money.dart` does not exist / `formatMoney` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/shared/money.dart

/// Formats integer minor units (cents) as a plain 2-decimal string.
String formatMoney(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final frac = (abs % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$whole.$frac';
}

/// Parses a non-negative decimal string into integer minor units (cents).
/// Returns null if the input is not a valid non-negative number.
int? parseMoney(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final value = double.tryParse(trimmed);
  if (value == null || value < 0 || value.isNaN || value.isInfinite) {
    return null;
  }
  return (value * 100).round();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/money_test.dart`
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/money.dart test/money_test.dart
git commit -m "feat: add integer-cents money helpers"
```

---

### Task 3: Domain enums and models

Plain immutable Dart — no Flutter, no DB imports.

**Files:**
- Create: `lib/domain/enums.dart`
- Create: `lib/domain/models.dart`

- [ ] **Step 1: Write the enums**

```dart
// lib/domain/enums.dart

enum UserRole {
  cashier,
  manager,
  admin;

  /// Manager and admin may manage products; cashier may not.
  bool get canManageProducts => this == manager || this == admin;

  static UserRole fromName(String name) =>
      UserRole.values.firstWhere((r) => r.name == name);
}

enum SaleStatus {
  completed;

  static SaleStatus fromName(String name) =>
      SaleStatus.values.firstWhere((s) => s.name == name);
}

enum PaymentMethod {
  cash;

  static PaymentMethod fromName(String name) =>
      PaymentMethod.values.firstWhere((m) => m.name == name);
}

enum MovementType {
  sale,
  seed,
  adjustment;

  static MovementType fromName(String name) =>
      MovementType.values.firstWhere((t) => t.name == name);
}
```

- [ ] **Step 2: Write the models**

```dart
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
```

- [ ] **Step 3: Verify it analyzes**

Run: `flutter analyze lib/domain`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/domain/enums.dart lib/domain/models.dart
git commit -m "feat: add domain enums and models"
```

---

### Task 4: Sale calculation logic

Pure functions that aggregate cart lines and compute change due. Test-driven.

**Files:**
- Create: `lib/domain/sale_calculator.dart`
- Test: `test/sale_calculator_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/sale_calculator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/domain/enums.dart';
import 'package:highbrid_pos/domain/models.dart';
import 'package:highbrid_pos/domain/sale_calculator.dart';

Product _product({int sellPrice = 100, double taxRate = 0.0}) => Product(
      id: 1,
      sku: 'SKU1',
      barcode: null,
      name: 'Test',
      description: '',
      categoryId: null,
      costPrice: 50,
      sellPrice: sellPrice,
      taxRate: taxRate,
      stockQty: 100,
      reorderLevel: 0,
      active: true,
    );

void main() {
  test('totals of an empty cart are all zero', () {
    expect(calculateTotals(const []), CartTotals.empty);
  });

  test('totals sum line subtotals and taxes', () {
    final lines = [
      CartLine(product: _product(sellPrice: 200, taxRate: 0.10), qty: 2),
      CartLine(product: _product(sellPrice: 150, taxRate: 0.00), qty: 1),
    ];
    final totals = calculateTotals(lines);
    expect(totals.subtotal, 550); // 400 + 150
    expect(totals.taxTotal, 40); // round(400*0.10) + 0
    expect(totals.total, 590);
  });

  test('line tax rounds to nearest cent', () {
    final line = CartLine(product: _product(sellPrice: 199, taxRate: 0.16), qty: 1);
    expect(line.lineTax, 32); // round(199 * 0.16 = 31.84)
    expect(line.lineTotal, 231);
  });

  test('changeDue is tendered minus total', () {
    expect(changeDue(tendered: 1000, total: 590), 410);
    expect(changeDue(tendered: 590, total: 590), 0);
  });

  test('isSufficientTender is false when tendered is below total', () {
    expect(isSufficientTender(tendered: 500, total: 590), isFalse);
    expect(isSufficientTender(tendered: 590, total: 590), isTrue);
    expect(isSufficientTender(tendered: 1000, total: 590), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/sale_calculator_test.dart`
Expected: FAIL — `sale_calculator.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/domain/sale_calculator.dart
import 'models.dart';

/// Aggregates a set of cart lines into subtotal, tax, and grand total.
CartTotals calculateTotals(List<CartLine> lines) {
  var subtotal = 0;
  var taxTotal = 0;
  for (final line in lines) {
    subtotal += line.lineSubtotal;
    taxTotal += line.lineTax;
  }
  return CartTotals(
    subtotal: subtotal,
    taxTotal: taxTotal,
    total: subtotal + taxTotal,
  );
}

/// Change owed to the customer. Never negative when tender is sufficient.
int changeDue({required int tendered, required int total}) => tendered - total;

/// True when the cash tendered covers the sale total.
bool isSufficientTender({required int tendered, required int total}) =>
    tendered >= total;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/sale_calculator_test.dart`
Expected: PASS — 5 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/sale_calculator.dart test/sale_calculator_test.dart
git commit -m "feat: add sale calculation logic"
```

---

### Task 5: drift database schema

**Files:**
- Create: `lib/data/db/app_database.dart`
- Generated: `lib/data/db/app_database.g.dart` (by build_runner)

- [ ] **Step 1: Write the table definitions and database class**

```dart
// lib/data/db/app_database.dart
import 'package:drift/drift.dart';

part 'app_database.g.dart';

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text().unique()();
  TextColumn get passwordHash => text()();
  TextColumn get fullName => text()();
  TextColumn get role => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
}

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sku => text().unique()();
  TextColumn get barcode => text().nullable().unique()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get costPrice => integer().withDefault(const Constant(0))();
  IntColumn get sellPrice => integer()();
  RealColumn get taxRate => real().withDefault(const Constant(0.0))();
  IntColumn get stockQty => integer().withDefault(const Constant(0))();
  IntColumn get reorderLevel => integer().withDefault(const Constant(0))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get referenceNo => text().unique()();
  IntColumn get cashierId => integer().references(Users, #id)();
  IntColumn get subtotal => integer()();
  IntColumn get taxTotal => integer()();
  IntColumn get total => integer()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class SaleItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get nameSnapshot => text()();
  IntColumn get unitPrice => integer()();
  RealColumn get taxRate => real()();
  IntColumn get qty => integer()();
  IntColumn get lineTax => integer()();
  IntColumn get lineTotal => integer()();
}

class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id)();
  TextColumn get method => text()();
  IntColumn get amount => integer()();
  IntColumn get tendered => integer()();
  IntColumn get changeDue => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class StockMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get type => text()();
  IntColumn get qtyDelta => integer()();
  TextColumn get refType => text().nullable()();
  IntColumn get refId => integer().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [
  Users,
  Categories,
  Products,
  Sales,
  SaleItems,
  Payments,
  StockMovements,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
```

- [ ] **Step 2: Generate the drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: build succeeds; `lib/data/db/app_database.g.dart` is created.

- [ ] **Step 3: Verify it analyzes**

Run: `flutter analyze lib/data/db`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/data/db/app_database.dart lib/data/db/app_database.g.dart
git commit -m "feat: add drift database schema"
```

---

### Task 6: Database seeding

Seeds an admin user and a sample catalog on first run (when the `users` table is empty).

**Files:**
- Create: `lib/data/db/seed.dart`

- [ ] **Step 1: Write the seeding function**

```dart
// lib/data/db/seed.dart
import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import 'app_database.dart';

/// Seeds an admin user and a sample catalog if the database is empty.
/// Idempotent: does nothing when a user already exists.
Future<void> seedIfEmpty(AppDatabase db) async {
  final existing = await db.select(db.users).get();
  if (existing.isNotEmpty) return;

  await db.transaction(() async {
    await db.into(db.users).insert(UsersCompanion.insert(
          username: 'admin',
          passwordHash: BCrypt.hashpw('admin123', BCrypt.gensalt()),
          fullName: 'Store Admin',
          role: UserRole.admin.name,
        ));

    final groceries = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'Groceries'),
        );
    final drinks = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'Drinks'),
        );

    final samples = <ProductsCompanion>[
      ProductsCompanion.insert(
        sku: 'GRC-001',
        barcode: const Value('1000000000017'),
        name: 'White Bread 400g',
        categoryId: Value(groceries),
        costPrice: const Value(80),
        sellPrice: 120,
        taxRate: const Value(0.0),
        stockQty: const Value(50),
        reorderLevel: const Value(10),
      ),
      ProductsCompanion.insert(
        sku: 'GRC-002',
        barcode: const Value('1000000000024'),
        name: 'Rice 2kg',
        categoryId: Value(groceries),
        costPrice: const Value(300),
        sellPrice: 450,
        taxRate: const Value(0.16),
        stockQty: const Value(40),
        reorderLevel: const Value(8),
      ),
      ProductsCompanion.insert(
        sku: 'DRK-001',
        barcode: const Value('1000000000031'),
        name: 'Cola 500ml',
        categoryId: Value(drinks),
        costPrice: const Value(60),
        sellPrice: 100,
        taxRate: const Value(0.16),
        stockQty: const Value(120),
        reorderLevel: const Value(24),
      ),
      ProductsCompanion.insert(
        sku: 'DRK-002',
        barcode: const Value('1000000000048'),
        name: 'Water 1L',
        categoryId: Value(drinks),
        costPrice: const Value(30),
        sellPrice: 60,
        taxRate: const Value(0.0),
        stockQty: const Value(200),
        reorderLevel: const Value(48),
      ),
    ];

    for (final p in samples) {
      final id = await db.into(db.products).insert(p);
      await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
            productId: id,
            type: MovementType.seed.name,
            qtyDelta: p.stockQty.value,
            note: const Value('Initial seed stock'),
          ));
    }
  });
}
```

- [ ] **Step 2: Verify it analyzes**

Run: `flutter analyze lib/data/db/seed.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/data/db/seed.dart
git commit -m "feat: add first-run database seeding"
```

---

### Task 7: Repositories

Four repositories wrap the drift database and return domain models. Test-driven against an
in-memory database.

**Files:**
- Create: `lib/data/repositories/auth_repository.dart`
- Create: `lib/data/repositories/product_repository.dart`
- Create: `lib/data/repositories/sale_repository.dart`
- Create: `lib/data/repositories/report_repository.dart`
- Test: `test/repositories_test.dart`

- [ ] **Step 1: Write the auth repository**

```dart
// lib/data/repositories/auth_repository.dart
import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../db/app_database.dart';

class AuthRepository {
  AuthRepository(this._db);
  final AppDatabase _db;

  /// Returns the user on a correct password for an active account, else null.
  Future<AppUser?> login(String username, String password) async {
    final row = await (_db.select(_db.users)
          ..where((u) => u.username.equals(username)))
        .getSingleOrNull();
    if (row == null || !row.active) return null;
    if (!BCrypt.checkpw(password, row.passwordHash)) return null;
    return _toUser(row);
  }

  AppUser _toUser(User row) => AppUser(
        id: row.id,
        username: row.username,
        fullName: row.fullName,
        role: UserRole.fromName(row.role),
        active: row.active,
      );
}
```

- [ ] **Step 2: Write the product repository**

```dart
// lib/data/repositories/product_repository.dart
import 'package:drift/drift.dart';

import '../../domain/models.dart';
import '../db/app_database.dart';

class ProductRepository {
  ProductRepository(this._db);
  final AppDatabase _db;

  Future<List<Product>> allProducts({bool activeOnly = false}) async {
    final query = _db.select(_db.products);
    if (activeOnly) query.where((p) => p.active.equals(true));
    query.orderBy([(p) => OrderingTerm(expression: p.name)]);
    final rows = await query.get();
    return rows.map(_toProduct).toList();
  }

  /// Active-product lookup by exact barcode, SKU, or case-insensitive name
  /// substring. Used by the POS search box.
  Future<List<Product>> search(String term) async {
    final t = term.trim();
    if (t.isEmpty) return allProducts(activeOnly: true);
    final like = '%${t.toLowerCase()}%';
    final query = _db.select(_db.products)
      ..where((p) =>
          p.active.equals(true) &
          (p.barcode.equals(t) |
              p.sku.equals(t) |
              p.name.lower().like(like)))
      ..orderBy([(p) => OrderingTerm(expression: p.name)]);
    final rows = await query.get();
    return rows.map(_toProduct).toList();
  }

  Future<Product> getById(int id) async {
    final row = await (_db.select(_db.products)..where((p) => p.id.equals(id)))
        .getSingle();
    return _toProduct(row);
  }

  Future<int> create({
    required String sku,
    String? barcode,
    required String name,
    String description = '',
    int? categoryId,
    required int costPrice,
    required int sellPrice,
    required double taxRate,
    required int stockQty,
    required int reorderLevel,
  }) async {
    return _db.transaction(() async {
      final id = await _db.into(_db.products).insert(ProductsCompanion.insert(
            sku: sku,
            barcode: Value(barcode),
            name: name,
            description: Value(description),
            categoryId: Value(categoryId),
            costPrice: Value(costPrice),
            sellPrice: sellPrice,
            taxRate: Value(taxRate),
            stockQty: Value(stockQty),
            reorderLevel: Value(reorderLevel),
          ));
      if (stockQty != 0) {
        await _db.into(_db.stockMovements).insert(
              StockMovementsCompanion.insert(
                productId: id,
                type: 'adjustment',
                qtyDelta: stockQty,
                note: const Value('Opening stock on product create'),
              ),
            );
      }
      return id;
    });
  }

  Future<void> update(
    int id, {
    required String sku,
    String? barcode,
    required String name,
    String description = '',
    int? categoryId,
    required int costPrice,
    required int sellPrice,
    required double taxRate,
    required int reorderLevel,
    required bool active,
  }) async {
    await (_db.update(_db.products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(
        sku: Value(sku),
        barcode: Value(barcode),
        name: Value(name),
        description: Value(description),
        categoryId: Value(categoryId),
        costPrice: Value(costPrice),
        sellPrice: Value(sellPrice),
        taxRate: Value(taxRate),
        reorderLevel: Value(reorderLevel),
        active: Value(active),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Deactivates a product (soft delete — keeps sale history intact).
  Future<void> deactivate(int id) async {
    await (_db.update(_db.products)..where((p) => p.id.equals(id)))
        .write(ProductsCompanion(
      active: const Value(false),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<List<Category>> allCategories() async {
    final rows = await (_db.select(_db.categories)
          ..orderBy([(c) => OrderingTerm(expression: c.name)]))
        .get();
    return rows.map((c) => Category(id: c.id, name: c.name)).toList();
  }

  Product _toProduct(ProductData row) => Product(
        id: row.id,
        sku: row.sku,
        barcode: row.barcode,
        name: row.name,
        description: row.description,
        categoryId: row.categoryId,
        costPrice: row.costPrice,
        sellPrice: row.sellPrice,
        taxRate: row.taxRate,
        stockQty: row.stockQty,
        reorderLevel: row.reorderLevel,
        active: row.active,
      );
}
```

> Note: drift names the row class for table `Products` as `Product` by default, which
> collides with our domain `Product`. The schema in Task 5 must add
> `@DataClassName('ProductData')` above the `Products` table class. Apply that now if not
> already present, and re-run build_runner.

- [ ] **Step 3: Add the `@DataClassName` annotation to the schema**

In `lib/data/db/app_database.dart`, change the `Products` declaration to:

```dart
@DataClassName('ProductData')
class Products extends Table {
```

Then run: `dart run build_runner build --delete-conflicting-outputs`
Expected: regenerates `app_database.g.dart` with the `ProductData` row class.

- [ ] **Step 4: Write the sale repository**

```dart
// lib/data/repositories/sale_repository.dart
import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../domain/sale_calculator.dart';
import '../db/app_database.dart';

class InsufficientStockException implements Exception {
  InsufficientStockException(this.productName);
  final String productName;
  @override
  String toString() => 'Insufficient stock for $productName';
}

class SaleRepository {
  SaleRepository(this._db);
  final AppDatabase _db;

  /// Records a completed cash sale: writes sale, items, payment, and stock
  /// movements, and deducts product stock — all in one transaction.
  /// Throws [InsufficientStockException] if any line exceeds available stock.
  Future<SaleRecord> completeCashSale({
    required int cashierId,
    required List<CartLine> lines,
    required int tendered,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('Cannot complete a sale with an empty cart');
    }
    final totals = calculateTotals(lines);

    return _db.transaction(() async {
      // Re-check stock inside the transaction.
      for (final line in lines) {
        final current = await (_db.select(_db.products)
              ..where((p) => p.id.equals(line.product.id)))
            .getSingle();
        if (current.stockQty < line.qty) {
          throw InsufficientStockException(current.name);
        }
      }

      final reference = await _nextReference();
      final saleId = await _db.into(_db.sales).insert(SalesCompanion.insert(
            referenceNo: reference,
            cashierId: cashierId,
            subtotal: totals.subtotal,
            taxTotal: totals.taxTotal,
            total: totals.total,
            status: SaleStatus.completed.name,
          ));

      for (final line in lines) {
        await _db.into(_db.saleItems).insert(SaleItemsCompanion.insert(
              saleId: saleId,
              productId: line.product.id,
              nameSnapshot: line.product.name,
              unitPrice: line.unitPrice,
              taxRate: line.product.taxRate,
              qty: line.qty,
              lineTax: line.lineTax,
              lineTotal: line.lineTotal,
            ));
        await (_db.update(_db.products)
              ..where((p) => p.id.equals(line.product.id)))
            .write(ProductsCompanion.custom(
          stockQty: _db.products.stockQty - Variable(line.qty),
        ));
        await _db.into(_db.stockMovements).insert(
              StockMovementsCompanion.insert(
                productId: line.product.id,
                type: MovementType.sale.name,
                qtyDelta: -line.qty,
                refType: const Value('sale'),
                refId: Value(saleId),
              ),
            );
      }

      await _db.into(_db.payments).insert(PaymentsCompanion.insert(
            saleId: saleId,
            method: PaymentMethod.cash.name,
            amount: totals.total,
            tendered: tendered,
            changeDue: changeDue(tendered: tendered, total: totals.total),
          ));

      return getById(saleId);
    });
  }

  Future<SaleRecord> getById(int saleId) async {
    final sale = await (_db.select(_db.sales)
          ..where((s) => s.id.equals(saleId)))
        .getSingle();
    final cashier = await (_db.select(_db.users)
          ..where((u) => u.id.equals(sale.cashierId)))
        .getSingle();
    final payment = await (_db.select(_db.payments)
          ..where((p) => p.saleId.equals(saleId)))
        .getSingle();
    final items = await (_db.select(_db.saleItems)
          ..where((i) => i.saleId.equals(saleId)))
        .get();
    return SaleRecord(
      id: sale.id,
      referenceNo: sale.referenceNo,
      cashierId: sale.cashierId,
      cashierName: cashier.fullName,
      subtotal: sale.subtotal,
      taxTotal: sale.taxTotal,
      total: sale.total,
      tendered: payment.tendered,
      changeDue: payment.changeDue,
      createdAt: sale.createdAt,
      lines: items
          .map((i) => SaleLine(
                nameSnapshot: i.nameSnapshot,
                unitPrice: i.unitPrice,
                taxRate: i.taxRate,
                qty: i.qty,
                lineTax: i.lineTax,
                lineTotal: i.lineTotal,
              ))
          .toList(),
    );
  }

  /// Builds the next per-day sale reference: YYYYMMDD-NNNN.
  Future<String> _nextReference() async {
    final now = DateTime.now();
    final prefix = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final todayCount = await (_db.select(_db.sales)
          ..where((s) => s.referenceNo.like('$prefix-%')))
        .get();
    final seq = (todayCount.length + 1).toString().padLeft(4, '0');
    return '$prefix-$seq';
  }
}
```

- [ ] **Step 5: Write the report repository**

```dart
// lib/data/repositories/report_repository.dart
import '../../domain/models.dart';
import '../db/app_database.dart';

class ReportRepository {
  ReportRepository(this._db);
  final AppDatabase _db;

  /// Aggregates all completed sales for the given calendar day.
  Future<DailySummary> dailySummary(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final sales = await (_db.select(_db.sales)
          ..where((s) =>
              s.createdAt.isBiggerOrEqualValue(start) &
              s.createdAt.isSmallerThanValue(end)))
        .get();
    var subtotal = 0;
    var taxTotal = 0;
    var total = 0;
    for (final s in sales) {
      subtotal += s.subtotal;
      taxTotal += s.taxTotal;
      total += s.total;
    }
    return DailySummary(
      day: start,
      saleCount: sales.length,
      subtotal: subtotal,
      taxTotal: taxTotal,
      total: total,
    );
  }
}
```

- [ ] **Step 6: Write the repository tests**

```dart
// test/repositories_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';
import 'package:highbrid_pos/data/db/seed.dart';
import 'package:highbrid_pos/data/repositories/auth_repository.dart';
import 'package:highbrid_pos/data/repositories/product_repository.dart';
import 'package:highbrid_pos/data/repositories/report_repository.dart';
import 'package:highbrid_pos/data/repositories/sale_repository.dart';
import 'package:highbrid_pos/domain/models.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedIfEmpty(db);
  });

  tearDown(() async => db.close());

  test('seed creates an admin user and sample products', () async {
    final products = await ProductRepository(db).allProducts();
    expect(products.length, 4);
    final auth = await AuthRepository(db).login('admin', 'admin123');
    expect(auth, isNotNull);
    expect(auth!.role.canManageProducts, isTrue);
  });

  test('login rejects a wrong password', () async {
    expect(await AuthRepository(db).login('admin', 'wrong'), isNull);
  });

  test('search finds a product by barcode and by name substring', () async {
    final repo = ProductRepository(db);
    expect((await repo.search('1000000000017')).single.name, 'White Bread 400g');
    expect((await repo.search('cola')).single.sku, 'DRK-001');
  });

  test('completeCashSale records the sale and deducts stock', () async {
    final products = ProductRepository(db);
    final cola = (await products.search('cola')).single;
    final before = cola.stockQty;

    final sale = await SaleRepository(db).completeCashSale(
      cashierId: 1,
      lines: [CartLine(product: cola, qty: 3)],
      tendered: 1000,
    );

    expect(sale.referenceNo, matches(r'^\d{8}-0001$'));
    expect(sale.total, 348); // 3 * 100 = 300 subtotal, +48 tax (16%)
    expect(sale.changeDue, 652);

    final after = await products.getById(cola.id);
    expect(after.stockQty, before - 3);
  });

  test('completeCashSale throws when stock is insufficient', () async {
    final products = ProductRepository(db);
    final cola = (await products.search('cola')).single;
    expect(
      () => SaleRepository(db).completeCashSale(
        cashierId: 1,
        lines: [CartLine(product: cola, qty: cola.stockQty + 1)],
        tendered: 100000,
      ),
      throwsA(isA<InsufficientStockException>()),
    );
  });

  test('sale references increment per day', () async {
    final products = ProductRepository(db);
    final water = (await products.search('water')).single;
    final repo = SaleRepository(db);
    final s1 = await repo.completeCashSale(
        cashierId: 1, lines: [CartLine(product: water, qty: 1)], tendered: 100);
    final s2 = await repo.completeCashSale(
        cashierId: 1, lines: [CartLine(product: water, qty: 1)], tendered: 100);
    expect(s1.referenceNo.endsWith('-0001'), isTrue);
    expect(s2.referenceNo.endsWith('-0002'), isTrue);
  });

  test('dailySummary aggregates today\'s sales', () async {
    final products = ProductRepository(db);
    final water = (await products.search('water')).single;
    await SaleRepository(db).completeCashSale(
        cashierId: 1, lines: [CartLine(product: water, qty: 2)], tendered: 200);

    final summary = await ReportRepository(db).dailySummary(DateTime.now());
    expect(summary.saleCount, 1);
    expect(summary.total, 120); // 2 * 60, no tax
  });
}
```

- [ ] **Step 7: Run the repository tests**

Run: `flutter test test/repositories_test.dart`
Expected: PASS — 7 tests.

- [ ] **Step 8: Commit**

```bash
git add lib/data/repositories test/repositories_test.dart lib/data/db/app_database.dart lib/data/db/app_database.g.dart
git commit -m "feat: add auth, product, sale, and report repositories"
```

---

### Task 8: Riverpod providers

Wires the database and repositories into Riverpod so screens can read them.

**Files:**
- Create: `lib/providers.dart`

- [ ] **Step 1: Write the providers**

```dart
// lib/providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/db/app_database.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/product_repository.dart';
import 'data/repositories/report_repository.dart';
import 'data/repositories/sale_repository.dart';

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
```

- [ ] **Step 2: Verify it analyzes**

Run: `flutter analyze lib/providers.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/providers.dart
git commit -m "feat: add Riverpod database and repository providers"
```

---

### Task 9: Theme and shared formatting

**Files:**
- Create: `lib/shared/theme.dart`

- [ ] **Step 1: Write the theme and formatting helpers**

```dart
// lib/shared/theme.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1565C0),
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
  );
}

final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');
final _dayFmt = DateFormat('EEEE, d MMMM yyyy');

String formatDateTime(DateTime dt) => _dateFmt.format(dt);
String formatDay(DateTime dt) => _dayFmt.format(dt);
```

- [ ] **Step 2: Verify it analyzes**

Run: `flutter analyze lib/shared/theme.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/shared/theme.dart
git commit -m "feat: add app theme and date formatting"
```

---

### Task 10: Auth feature — controller and login screen

**Files:**
- Create: `lib/features/auth/auth_controller.dart`
- Create: `lib/features/auth/login_screen.dart`
- Test: `test/login_screen_test.dart`

- [ ] **Step 1: Write the auth controller**

```dart
// lib/features/auth/auth_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../providers.dart';

/// Holds the currently logged-in user, or null when logged out.
class AuthController extends StateNotifier<AppUser?> {
  AuthController(this._ref) : super(null);
  final Ref _ref;

  /// Attempts login. Returns null on success, or an error message on failure.
  Future<String?> login(String username, String password) async {
    if (username.trim().isEmpty || password.isEmpty) {
      return 'Enter a username and password.';
    }
    final user = await _ref
        .read(authRepositoryProvider)
        .login(username.trim(), password);
    if (user == null) {
      return 'Invalid username or password, or the account is disabled.';
    }
    state = user;
    return null;
  }

  void logout() => state = null;
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AppUser?>(
  (ref) => AuthController(ref),
);
```

- [ ] **Step 2: Write the login screen**

```dart
// lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref
        .read(authControllerProvider.notifier)
        .login(_username.text, _password.text);
    if (mounted) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

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
                children: [
                  Text('HighbridPOS',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  const Text('Cashier sign in'),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _username,
                    decoration: const InputDecoration(labelText: 'Username'),
                    autofocus: true,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Sign in'),
                    ),
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
```

- [ ] **Step 3: Write the login widget test**

```dart
// test/login_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';
import 'package:highbrid_pos/data/db/seed.dart';
import 'package:highbrid_pos/features/auth/auth_controller.dart';
import 'package:highbrid_pos/features/auth/login_screen.dart';
import 'package:highbrid_pos/providers.dart';

Future<ProviderContainer> _seededContainer() async {
  final db = AppDatabase(NativeDatabase.memory());
  await seedIfEmpty(db);
  return ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db)],
  );
}

void main() {
  testWidgets('shows an error on a wrong password', (tester) async {
    final container = await _seededContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LoginScreen()),
    ));

    await tester.enterText(find.byType(TextField).first, 'admin');
    await tester.enterText(find.byType(TextField).last, 'nope');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Invalid username'), findsOneWidget);
    expect(container.read(authControllerProvider), isNull);
  });

  testWidgets('logs in with correct credentials', (tester) async {
    final container = await _seededContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LoginScreen()),
    ));

    await tester.enterText(find.byType(TextField).first, 'admin');
    await tester.enterText(find.byType(TextField).last, 'admin123');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(container.read(authControllerProvider)?.username, 'admin');
  });
}
```

- [ ] **Step 4: Run the login test**

Run: `flutter test test/login_screen_test.dart`
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth test/login_screen_test.dart
git commit -m "feat: add auth controller and login screen"
```

---

### Task 11: App shell, routing, and entry point

The shell switches between login and the main app based on auth state, and provides
navigation for logged-in users.

**Files:**
- Create: `lib/app.dart`
- Create: `lib/features/home_shell.dart`
- Modify: `lib/main.dart` (replace generated content)

- [ ] **Step 1: Write the home shell**

```dart
// lib/features/home_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_controller.dart';
import 'pos/sale_screen.dart';
import 'products/product_list_screen.dart';
import 'reports/daily_summary_screen.dart';

/// Main navigation shell shown to a logged-in user.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider);
    if (user == null) return const SizedBox.shrink();

    final destinations = <({IconData icon, String label, Widget page})>[
      (icon: Icons.point_of_sale, label: 'Sell', page: const SaleScreen()),
      if (user.role.canManageProducts)
        (
          icon: Icons.inventory_2,
          label: 'Products',
          page: const ProductListScreen()
        ),
      (
        icon: Icons.summarize,
        label: 'Daily Summary',
        page: const DailySummaryScreen()
      ),
    ];
    final safeIndex = _index.clamp(0, destinations.length - 1);

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            selectedIndex: safeIndex,
            onDestinationSelected: (i) => setState(() => _index = i),
            leading: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('HighbridPOS',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(user.fullName,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextButton.icon(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).logout(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Log out'),
                  ),
                ),
              ),
            ),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: destinations[safeIndex].page),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Write the app widget**

```dart
// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/home_shell.dart';
import 'shared/theme.dart';

class HighbridPosApp extends ConsumerWidget {
  const HighbridPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    return MaterialApp(
      title: 'HighbridPOS',
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      home: user == null ? const LoginScreen() : const HomeShell(),
    );
  }
}
```

- [ ] **Step 3: Replace `lib/main.dart`**

```dart
// lib/main.dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/db/app_database.dart';
import 'data/db/seed.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, 'highbrid_pos.sqlite'));
  final db = AppDatabase(NativeDatabase(file));
  await seedIfEmpty(db);

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const HighbridPosApp(),
    ),
  );
}
```

- [ ] **Step 4: Verify it analyzes**

Run: `flutter analyze lib/main.dart lib/app.dart lib/features/home_shell.dart`
Expected: `No issues found!` (the product/POS/report screens are created in later
tasks — if analyze runs before them, expect missing-import errors that resolve once
Tasks 12–14 land. Run this step's analyze after Task 14 if executing strictly in order,
or stub the three screens now.)

> To keep each task independently analyzable, create minimal stub screens now and flesh
> them out in their tasks. Create `lib/features/pos/sale_screen.dart`,
> `lib/features/products/product_list_screen.dart`, and
> `lib/features/reports/daily_summary_screen.dart` each containing a placeholder:
>
> ```dart
> import 'package:flutter/material.dart';
> class SaleScreen extends StatelessWidget {
>   const SaleScreen({super.key});
>   @override
>   Widget build(BuildContext context) => const Placeholder();
> }
> ```
>
> (Rename the class per file: `SaleScreen`, `ProductListScreen`, `DailySummaryScreen`.)

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/app.dart lib/features/home_shell.dart lib/features/pos lib/features/products lib/features/reports
git commit -m "feat: add app shell, routing, and entry point with stub screens"
```

---

### Task 12: Product management feature

**Files:**
- Create: `lib/features/products/product_controller.dart`
- Replace stub: `lib/features/products/product_list_screen.dart`
- Create: `lib/features/products/product_form_screen.dart`

- [ ] **Step 1: Write the product controller**

```dart
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
```

- [ ] **Step 2: Write the product form screen**

```dart
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
                value: _categoryId,
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
```

- [ ] **Step 3: Replace the product list screen stub**

```dart
// lib/features/products/product_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
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
```

- [ ] **Step 4: Verify it analyzes**

Run: `flutter analyze lib/features/products`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/products
git commit -m "feat: add product management list and form"
```

---

### Task 13: POS sale feature

The core checkout: search/add products, manage the cart, take cash payment.

**Files:**
- Create: `lib/features/pos/cart_controller.dart`
- Create: `lib/features/pos/payment_dialog.dart`
- Replace stub: `lib/features/pos/sale_screen.dart`
- Test: `test/sale_screen_test.dart`

- [ ] **Step 1: Write the cart controller**

```dart
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
```

- [ ] **Step 2: Write the payment dialog**

```dart
// lib/features/pos/payment_dialog.dart
import 'package:flutter/material.dart';

import '../../domain/sale_calculator.dart';
import '../../shared/money.dart';

/// Cash-payment dialog. Resolves to the tendered amount in cents, or null
/// if cancelled.
class PaymentDialog extends StatefulWidget {
  const PaymentDialog({super.key, required this.total});
  final int total;

  static Future<int?> show(BuildContext context, int total) =>
      showDialog<int>(
        context: context,
        builder: (_) => PaymentDialog(total: total),
      );

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final _tendered = TextEditingController();

  @override
  void dispose() {
    _tendered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tendered = parseMoney(_tendered.text);
    final sufficient = tendered != null &&
        isSufficientTender(tendered: tendered, total: widget.total);
    final change = sufficient
        ? changeDue(tendered: tendered, total: widget.total)
        : 0;

    return AlertDialog(
      title: const Text('Cash payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total due'),
              Text(formatMoney(widget.total),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tendered,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Cash tendered'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Change due'),
              Text(formatMoney(change),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              sufficient ? () => Navigator.of(context).pop(tendered) : null,
          child: const Text('Complete sale'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Replace the sale screen stub**

```dart
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
                                            Text(formatMoney(p.sellPrice)),
                                            Text('Stock ${p.stockQty}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall),
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
```

- [ ] **Step 4: Write the sale screen widget test**

```dart
// test/sale_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';
import 'package:highbrid_pos/data/db/seed.dart';
import 'package:highbrid_pos/features/auth/auth_controller.dart';
import 'package:highbrid_pos/features/pos/cart_controller.dart';
import 'package:highbrid_pos/features/pos/sale_screen.dart';
import 'package:highbrid_pos/providers.dart';

void main() {
  testWidgets('adding a product shows it in the cart with totals',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await seedIfEmpty(db);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    // Log in so the checkout path has a cashier.
    await container
        .read(authControllerProvider.notifier)
        .login('admin', 'admin123');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SaleScreen()),
    ));
    await tester.pumpAndSettle();

    // Tap the first product card.
    await tester.tap(find.text('Cola 500ml').first);
    await tester.pumpAndSettle();

    expect(container.read(cartControllerProvider).length, 1);
    expect(container.read(cartControllerProvider.notifier).totals.total, 116);
  });
}
```

- [ ] **Step 5: Run the sale screen test**

Run: `flutter test test/sale_screen_test.dart`
Expected: PASS — 1 test. (This task depends on `receipt.dart` from Task 14 for the
import to resolve. Execute Task 14 first, or temporarily stub `showReceiptDialog`. The
recommended order is Task 14 before running this step.)

- [ ] **Step 6: Commit**

```bash
git add lib/features/pos test/sale_screen_test.dart
git commit -m "feat: add POS sale screen, cart, and cash payment"
```

---

### Task 14: Receipt and daily summary

**Files:**
- Create: `lib/features/pos/receipt.dart`
- Replace stub: `lib/features/reports/daily_summary_screen.dart`
- Replace: `test/widget_test.dart` (generated file — delete, it references the old app)

- [ ] **Step 1: Write the receipt**

```dart
// lib/features/pos/receipt.dart
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/models.dart';
import '../../shared/money.dart';
import '../../shared/theme.dart';

/// Builds a printable PDF receipt for a completed sale.
Future<pw.Document> buildReceiptPdf(SaleRecord sale) async {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text('HighbridPOS',
                style: pw.TextStyle(
                    fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Receipt ${sale.referenceNo}'),
          pw.Text(formatDateTime(sale.createdAt)),
          pw.Text('Cashier: ${sale.cashierName}'),
          pw.Divider(),
          for (final line in sale.lines)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                    child: pw.Text(
                        '${line.qty} x ${line.nameSnapshot}')),
                pw.Text(formatMoney(line.lineTotal)),
              ],
            ),
          pw.Divider(),
          _pdfRow('Subtotal', sale.subtotal),
          _pdfRow('Tax', sale.taxTotal),
          _pdfRow('Total', sale.total, bold: true),
          _pdfRow('Cash', sale.tendered),
          _pdfRow('Change', sale.changeDue),
          pw.SizedBox(height: 8),
          pw.Center(child: pw.Text('Thank you for shopping with us')),
        ],
      ),
    ),
  );
  return doc;
}

pw.Widget _pdfRow(String label, int value, {bool bold = false}) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label,
            style: bold
                ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                : null),
        pw.Text(formatMoney(value),
            style: bold
                ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                : null),
      ],
    );

/// Shows the on-screen receipt with an option to export/print the PDF.
Future<void> showReceiptDialog(BuildContext context, SaleRecord sale) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Sale ${sale.referenceNo}'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(formatDateTime(sale.createdAt)),
            Text('Cashier: ${sale.cashierName}'),
            const Divider(),
            for (final line in sale.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child:
                            Text('${line.qty} x ${line.nameSnapshot}')),
                    Text(formatMoney(line.lineTotal)),
                  ],
                ),
              ),
            const Divider(),
            _ScreenRow(label: 'Subtotal', value: sale.subtotal),
            _ScreenRow(label: 'Tax', value: sale.taxTotal),
            _ScreenRow(label: 'Total', value: sale.total, bold: true),
            _ScreenRow(label: 'Cash', value: sale.tendered),
            _ScreenRow(label: 'Change', value: sale.changeDue, bold: true),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Print / PDF'),
          onPressed: () async {
            final doc = await buildReceiptPdf(sale);
            await Printing.layoutPdf(onLayout: (_) => doc.save());
          },
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

class _ScreenRow extends StatelessWidget {
  const _ScreenRow(
      {required this.label, required this.value, this.bold = false});
  final String label;
  final int value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(formatMoney(value), style: style)],
      ),
    );
  }
}
```

- [ ] **Step 2: Replace the daily summary screen stub**

```dart
// lib/features/reports/daily_summary_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../providers.dart';
import '../../shared/money.dart';
import '../../shared/theme.dart';

final _dailySummaryProvider = FutureProvider.autoDispose<DailySummary>(
  (ref) => ref.watch(reportRepositoryProvider).dailySummary(DateTime.now()),
);

class DailySummaryScreen extends ConsumerWidget {
  const DailySummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(_dailySummaryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_dailySummaryProvider),
          ),
        ],
      ),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load summary: $e')),
        data: (s) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(formatDay(s.day),
                        style: Theme.of(context).textTheme.titleMedium),
                    const Divider(height: 24),
                    _row('Sales completed', s.saleCount.toString()),
                    _row('Subtotal', formatMoney(s.subtotal)),
                    _row('Tax collected', formatMoney(s.taxTotal)),
                    const Divider(height: 24),
                    _row('Total takings', formatMoney(s.total), bold: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight:
                        bold ? FontWeight.bold : FontWeight.normal)),
            Text(value,
                style: TextStyle(
                    fontSize: bold ? 20 : 14,
                    fontWeight:
                        bold ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      );
}
```

- [ ] **Step 3: Remove the stale generated widget test**

```bash
rm test/widget_test.dart
```

(The generated `widget_test.dart` references the removed counter app and would fail.)

- [ ] **Step 4: Run the full analyzer and test suite**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: all tests PASS — `money_test`, `sale_calculator_test`, `repositories_test`,
`login_screen_test`, `sale_screen_test` (total 18 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/pos/receipt.dart lib/features/reports/daily_summary_screen.dart
git rm test/widget_test.dart
git commit -m "feat: add receipt printing and daily sales summary"
```

---

### Task 15: Manual smoke test and run

**Files:** none — verification only.

- [ ] **Step 1: Launch the app**

Run: `flutter run -d linux`
Expected: the login screen appears.

- [ ] **Step 2: Walk the happy path**

1. Log in as `admin` / `admin123`. The home shell appears with Sell, Products, and
   Daily Summary in the rail.
2. Open **Products** → **New product**, create a product, confirm it appears in the list.
3. Open **Sell**, search for "cola", click the card twice → cart shows qty 2, totals
   update with tax.
4. Click **Take cash payment**, enter an amount above the total → change due shows;
   complete the sale.
5. The receipt dialog appears; click **Print / PDF** → a PDF preview opens.
6. Open **Daily Summary** → sale count and takings reflect the sale.
7. Log out → returns to the login screen.
8. Confirm stock: re-open the product in **Products**; `stockQty` dropped by 2.

- [ ] **Step 2: Verify the offline guarantee**

The app makes no network calls. Disconnect the network and repeat Step 2 — behaviour is
identical (the database is local).

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "chore: HighbridPOS Slice 1 complete" --allow-empty
```

---

## Self-Review Notes

**Spec coverage** — every Slice 1 spec item maps to a task: auth/roles (Tasks 7, 10, 11);
product management (Task 12); core sale loop incl. search, barcode, cart, quantity, tax,
totals, cash payment, stock deduction (Tasks 4, 7, 13); receipts on-screen + PDF
(Task 14); daily summary (Task 14); integer-cents money (Task 2); single-transaction sale
(Task 7); `YYYYMMDD-NNNN` references (Task 7); first-run seed (Task 6); per-line tax
snapshot (Tasks 5, 7).

**Cross-task type consistency** — `Product`, `CartLine`, `CartTotals`, `SaleRecord`,
`SaleLine`, `DailySummary` defined in Task 3 and used unchanged thereafter. The drift
row-class collision on `Product` is resolved in Task 7 Step 3 via `@DataClassName`.

**Known ordering note** — Task 13's `sale_screen.dart` imports `receipt.dart` (Task 14).
Either execute Task 14's Step 1 before Task 13's Step 5, or stub `showReceiptDialog`.
This is called out inline in both tasks.
