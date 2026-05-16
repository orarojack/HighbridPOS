// test/returns_flow_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';
import 'package:highbrid_pos/data/db/seed.dart';
import 'package:highbrid_pos/data/repositories/return_repository.dart';
import 'package:highbrid_pos/data/repositories/sale_repository.dart';
import 'package:highbrid_pos/domain/models.dart';
import 'package:highbrid_pos/features/auth/auth_controller.dart';
import 'package:highbrid_pos/features/returns/returns_lookup_screen.dart';
import 'package:highbrid_pos/features/shift/shift_controller.dart';
import 'package:highbrid_pos/providers.dart';
import 'package:highbrid_pos/shared/theme.dart';

/// HighbridPOS is a desktop POS terminal; the returns screens live in a wide
/// shell. The default 800x600 test viewport is too narrow, so widen the
/// surface before pumping and reset it afterwards.
void _useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The result of [_setUp]: the container plus the seeded completed sale used
/// as the return's original.
class _Fixture {
  _Fixture(this.container, this.db, this.sale);
  final ProviderContainer container;
  final AppDatabase db;
  final SaleRecord sale;
}

/// Builds a container backed by a fresh in-memory database with the seeded
/// `cashier` signed in, an open shift, and one completed cash sale to return
/// against. The sale has 4 units of Rice 2kg and 2 units of White Bread 400g.
Future<_Fixture> _setUp(WidgetTester tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  await seedIfEmpty(db);
  final container = ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db)],
  );
  addTearDown(container.dispose);
  addTearDown(db.close);

  await container
      .read(authControllerProvider.notifier)
      .login('cashier', 'cashier123');

  // Open the shift via the controller so its provider state is current.
  final shift =
      await container.read(shiftControllerProvider.notifier).start(10000);

  final rice = await _product(db, 'GRC-002');
  final bread = await _product(db, 'GRC-001');
  final sale = await SaleRepository(db).completeCashSale(
    cashierId: 2,
    shiftId: shift.id,
    lines: [
      CartLine(product: rice, qty: 4),
      CartLine(product: bread, qty: 2),
    ],
    tendered: 1000000,
  );

  return _Fixture(container, db, sale);
}

Future<Product> _product(AppDatabase db, String sku) async {
  final row = await (db.select(db.products)..where((p) => p.sku.equals(sku)))
      .getSingle();
  return Product(
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

Widget _host(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: child),
    );

void main() {
  testWidgets('looking up an existing sale shows its lines', (tester) async {
    _useDesktopViewport(tester);
    final fx = await _setUp(tester);

    await tester.pumpWidget(
        _host(fx.container, const ReturnsLookupScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Sale reference number'),
        fx.sale.referenceNo);
    await tester.tap(find.widgetWithText(FilledButton, 'Find sale'));
    await tester.pumpAndSettle();

    // Routed to the select screen; the sale's lines are listed.
    expect(find.text('Choose what to return'), findsOneWidget);
    expect(find.text('Rice 2kg'), findsOneWidget);
    expect(find.text('White Bread 400g'), findsOneWidget);
  });

  testWidgets('looking up an unknown reference shows the not-found message',
      (tester) async {
    _useDesktopViewport(tester);
    final fx = await _setUp(tester);

    await tester.pumpWidget(
        _host(fx.container, const ReturnsLookupScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Sale reference number'),
        'NOPE-9999');
    await tester.tap(find.widgetWithText(FilledButton, 'Find sale'));
    await tester.pumpAndSettle();

    expect(find.text('No sale found for that reference number.'),
        findsOneWidget);
    // Still on the lookup screen — no routing happened.
    expect(find.text('Choose what to return'), findsNothing);
  });

  testWidgets('a partial-quantity selection drives the live refund total',
      (tester) async {
    _useDesktopViewport(tester);
    final fx = await _setUp(tester);

    await tester.pumpWidget(
        _host(fx.container, const ReturnsLookupScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Sale reference number'),
        fx.sale.referenceNo);
    await tester.tap(find.widgetWithText(FilledButton, 'Find sale'));
    await tester.pumpAndSettle();

    // Record return is disabled until something is selected.
    final recordBtn =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Record return'));
    expect(recordBtn.onPressed, isNull);

    // Bump Rice 2kg up to 2 units via the stepper.
    final riceTile = find.ancestor(
      of: find.text('Rice 2kg'),
      matching: find.byType(ListTile),
    );
    final plus = find.descendant(
      of: riceTile,
      matching: find.byIcon(Icons.add_circle_outline),
    );
    await tester.tap(plus);
    await tester.pump();
    await tester.tap(plus);
    await tester.pump();

    // The selected quantity shows 2 and the refund total is non-zero.
    expect(find.descendant(of: riceTile, matching: find.text('2')),
        findsOneWidget);
    expect(find.text(r'$0.00'), findsNothing);
    // The button is now enabled.
    final enabled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Record return'));
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets(
      'the stepper caps at the returnable quantity (over-return unreachable)',
      (tester) async {
    _useDesktopViewport(tester);
    final fx = await _setUp(tester);

    await tester.pumpWidget(
        _host(fx.container, const ReturnsLookupScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Sale reference number'),
        fx.sale.referenceNo);
    await tester.tap(find.widgetWithText(FilledButton, 'Find sale'));
    await tester.pumpAndSettle();

    // White Bread 400g sold 2 units. Tap the stepper three times — it must cap at 2.
    final breadTile = find.ancestor(
      of: find.text('White Bread 400g'),
      matching: find.byType(ListTile),
    );
    final plus = find.descendant(
      of: breadTile,
      matching: find.byIcon(Icons.add_circle_outline),
    );
    await tester.tap(plus);
    await tester.pump();
    await tester.tap(plus);
    await tester.pump();
    expect(find.descendant(of: breadTile, matching: find.text('2')),
        findsOneWidget);

    // At the cap, the increment button is disabled.
    final plusBtn = tester.widget<IconButton>(find.ancestor(
      of: plus,
      matching: find.byType(IconButton),
    ));
    expect(plusBtn.onPressed, isNull);
  });

  testWidgets(
      'recording a return goes through manager approval then shows the receipt',
      (tester) async {
    _useDesktopViewport(tester);
    final fx = await _setUp(tester);

    await tester.pumpWidget(
        _host(fx.container, const ReturnsLookupScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Sale reference number'),
        fx.sale.referenceNo);
    await tester.tap(find.widgetWithText(FilledButton, 'Find sale'));
    await tester.pumpAndSettle();

    // Select 2 units of Rice 2kg.
    final riceTile = find.ancestor(
      of: find.text('Rice 2kg'),
      matching: find.byType(ListTile),
    );
    final plus = find.descendant(
      of: riceTile,
      matching: find.byIcon(Icons.add_circle_outline),
    );
    await tester.tap(plus);
    await tester.pump();
    await tester.tap(plus);
    await tester.pump();

    // Tap Record return — the manager-approval dialog must appear first.
    await tester.tap(find.widgetWithText(FilledButton, 'Record return'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Approve:'), findsOneWidget);

    // No return is written yet.
    expect(await fx.db.select(fx.db.returns).get(), isEmpty);

    // Approve with the admin's username + password.
    await tester.enterText(
        find.widgetWithText(TextField, 'Username'), 'admin');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'admin123');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();

    // The return receipt appears.
    expect(find.text('RETURN / REFUND'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    // The return was persisted with the admin (user id 1) as approver.
    final returns = await fx.db.select(fx.db.returns).get();
    expect(returns, hasLength(1));
    expect(returns.single.approvedBy, 1);
    expect(returns.single.originalSaleId, fx.sale.id);
    final items = await fx.db.select(fx.db.returnItems).get();
    expect(items, hasLength(1));
    expect(items.single.qty, 2);
  });

  testWidgets('a cancelled manager approval records nothing', (tester) async {
    _useDesktopViewport(tester);
    final fx = await _setUp(tester);

    await tester.pumpWidget(
        _host(fx.container, const ReturnsLookupScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Sale reference number'),
        fx.sale.referenceNo);
    await tester.tap(find.widgetWithText(FilledButton, 'Find sale'));
    await tester.pumpAndSettle();

    final riceTile = find.ancestor(
      of: find.text('Rice 2kg'),
      matching: find.byType(ListTile),
    );
    await tester.tap(find.descendant(
        of: riceTile, matching: find.byIcon(Icons.add_circle_outline)));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Record return'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Approve:'), findsOneWidget);

    // Cancel the approval dialog.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // Nothing was recorded and no receipt is shown.
    expect(await fx.db.select(fx.db.returns).get(), isEmpty);
    expect(find.text('RETURN / REFUND'), findsNothing);
  });

  testWidgets(
      'a sale with every line fully returned shows "Nothing left to return"'
      ' and the Record button is not actionable',
      (tester) async {
    _useDesktopViewport(tester);
    final fx = await _setUp(tester);

    // Fully return all lines of the sale directly via the repository.
    final repo = ReturnRepository(fx.db);
    final draft = (await repo.findSaleForReturn(fx.sale.referenceNo))!;
    await repo.recordReturn(
      originalSaleId: fx.sale.id,
      cashierId: 2,
      shiftId: fx.container.read(shiftControllerProvider).valueOrNull!.id,
      reason: 'full return',
      approvedBy: 1,
      selectedLines: draft.lines
          .map((l) => l.copyWith(selectedQty: l.returnableQty))
          .toList(),
    );

    // Now look up the same sale on the select screen.
    await tester.pumpWidget(
        _host(fx.container, const ReturnsLookupScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Sale reference number'),
        fx.sale.referenceNo);
    await tester.tap(find.widgetWithText(FilledButton, 'Find sale'));
    await tester.pumpAndSettle();

    // The "Nothing left to return" message must be visible and include the
    // sale reference.
    expect(find.textContaining('Nothing left to return'), findsOneWidget);
    expect(find.textContaining(fx.sale.referenceNo), findsWidgets);

    // The Record return button must be disabled (onPressed is null).
    final recordBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Record return'));
    expect(recordBtn.onPressed, isNull);
  });
}
