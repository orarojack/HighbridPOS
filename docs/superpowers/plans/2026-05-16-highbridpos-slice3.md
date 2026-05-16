# HighbridPOS Slice 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add controlled returns and cash refunds to the HighbridPOS desktop POS — look up a completed sale, return full or partial line quantities with manager approval, refund cash, restock, and keep the cash drawer and reports honest.

**Architecture:** Same layered Flutter app (UI → Riverpod → repositories → drift SQLite, pure-Dart domain logic). Slice 3 extends the SQLite schema via a v2→v3 migration, adds return domain models + pure refund-calculation functions, a return repository, return UI, and refund-aware shift/report accounting. The repository seam is preserved.

**Tech Stack:** Flutter Desktop, drift (SQLite ORM), Riverpod, bcrypt, pdf + printing, build_runner. No new packages.

---

## Prerequisite

Slices 1 and 2 are complete; Slice 3 is built on branch `slice3-returns` (off
`slice2-pin-shifts`). Flutter SDK 3.41.9 is at `~/flutter`, on `PATH` via `~/.bashrc`.
Verification is `flutter analyze` + `flutter test` (no Linux desktop toolchain, so
`flutter run` is not used).

Design spec: `docs/superpowers/specs/2026-05-16-highbridpos-slice3-design.md`.

## Conventions carried from Slices 1–2

- Money is integer minor units (cents): `int`.
- drift row-class name collisions with domain classes are avoided with `@DataClassName`.
- Domain models are immutable, `final` fields, `const` constructors where possible,
  `==`/`hashCode` over all fields. `models.dart` imports only `enums.dart`.
- Enums expose `.name`, `fromName` (throws `ArgumentError`), `fromNameOrNull`.
- Repositories take `AppDatabase`, return DOMAIN models via private `_toX` mappers,
  wrap multi-write operations in `db.transaction`, define custom exceptions as
  `class X implements Exception`.
- drift migrations: an `addColumn` that adds a UNIQUE column is NOT allowed by SQLite —
  add the column plain, then `CREATE UNIQUE INDEX` (see Slice 2 Task 1).
- Widget tests use a desktop viewport helper (1400×900), an in-memory `AppDatabase` +
  `seedIfEmpty`, and `ProviderScope` overrides.
- `flutter analyze` must stay clean; a trivial deprecation rename / unused-import
  removal on the way is acceptable.
- TDD: failing test → see it fail → implement → see it pass → commit.

## File Structure

```
lib/data/db/app_database.dart        MODIFY — returns + return_items tables, payments.returnId, shifts.refundTotal, schemaVersion 3 + onUpgrade
lib/domain/enums.dart                MODIFY — add CashEventType.refund
lib/domain/models.dart               MODIFY — add ReturnLineDraft, ReturnDraft, ReturnRecord, ReturnLine
lib/domain/return_calculator.dart    CREATE — pure refund-total / per-line-tax functions
lib/domain/shift_calculator.dart     MODIFY — expectedCash gains a refunds parameter
lib/data/repositories/return_repository.dart  CREATE — sale lookup w/ returnable qty, atomic recordReturn
lib/data/repositories/shift_repository.dart   MODIFY — closeShift passes refundTotal to expectedCash
lib/data/repositories/report_repository.dart  MODIFY — dailySummary includes returns count + refund total
lib/providers.dart                   MODIFY — returnRepositoryProvider
lib/features/returns/return_controller.dart   CREATE — in-memory return draft state
lib/features/returns/returns_lookup_screen.dart   CREATE — find a sale by reference
lib/features/returns/return_select_screen.dart    CREATE — pick lines + quantities, confirm
lib/features/returns/return_receipt.dart          CREATE — return receipt widget + PDF
lib/features/home_shell.dart         MODIFY — "Returns" rail destination
lib/features/reports/daily_summary_screen.dart    MODIFY — show returns + refunds
test/return_calculator_test.dart     CREATE
test/return_migration_test.dart      CREATE
test/return_repository_test.dart     CREATE
test/returns_flow_test.dart          CREATE
```

---

### Task 1: Schema migration to version 3

**Files:**
- Modify: `lib/data/db/app_database.dart`
- Generated: `lib/data/db/app_database.g.dart`
- Test: `test/return_migration_test.dart`

- [ ] **Step 1: Add the new tables and columns**

In `lib/data/db/app_database.dart` add two tables (above `@DriftDatabase`):
```dart
@DataClassName('ReturnRow')
class Returns extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get referenceNo => text()(); // unique enforced via index in migration
  IntColumn get originalSaleId => integer().references(Sales, #id)();
  IntColumn get cashierId => integer().references(Users, #id)();
  IntColumn get shiftId => integer().nullable().references(Shifts, #id)();
  TextColumn get reason => text().withDefault(const Constant(''))();
  IntColumn get refundTotal => integer()();
  IntColumn get approvedBy => integer().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('ReturnItemRow')
class ReturnItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId => integer().references(Returns, #id)();
  IntColumn get saleItemId => integer().references(SaleItems, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get nameSnapshot => text()();
  IntColumn get qty => integer()();
  IntColumn get unitPrice => integer()();
  RealColumn get taxRate => real()();
  IntColumn get lineTax => integer()();
  IntColumn get lineTotal => integer()();
}
```
Add to `Payments`: `IntColumn get returnId => integer().nullable().references(Returns, #id)();`
Add to `Shifts`: `IntColumn get refundTotal => integer().withDefault(const Constant(0))();`
Add `Returns` and `ReturnItems` to `@DriftDatabase(tables: [...])`.

For `referenceNo` uniqueness: declare it as a plain `text()` column (NOT `.unique()`), and
enforce uniqueness with a `CREATE UNIQUE INDEX` in BOTH `onCreate` (via `beforeOpen` is
wrong — use a `customStatement` in the migration) and `onUpgrade`. Simplest consistent
approach: declare it plain `text()`, and in the `MigrationStrategy` add the unique index
in a shared helper called from both `onCreate` and `onUpgrade`. (This mirrors the Slice 2
staff_id approach and keeps created-v3 and upgraded-v3 identical.)

- [ ] **Step 2: schemaVersion 3 + onUpgrade**

Bump `schemaVersion` to `3`. Extend `MigrationStrategy.onUpgrade` (keep the existing
`from < 2` block):
```dart
onUpgrade: (m, from, to) async {
  if (from < 2) { /* ...existing Slice 2 block unchanged... */ }
  if (from < 3) {
    await m.createTable(returns);
    await m.createTable(returnItems);
    await m.addColumn(payments, payments.returnId);
    await m.addColumn(shifts, shifts.refundTotal);
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS returns_reference_no_unique '
      'ON returns (reference_no)');
  }
},
```
Also ensure the `returns_reference_no_unique` index is created for a fresh v3 database —
add the same `customStatement` to `onCreate` after `m.createAll()`.

- [ ] **Step 3: Regenerate drift code**

Run: `dart run build_runner build` (generous timeout). Confirm `ReturnRow` and
`ReturnItemRow` are generated.

- [ ] **Step 4: Migration test**

`test/return_migration_test.dart` — assert a fresh v3 `AppDatabase` has the `returns`
and `return_items` tables, `payments.return_id`, `shifts.refund_total`, and
`schemaVersion == 3`; and that a v2-shaped database upgrades to v3 without data loss
(follow the pattern in `test/migration_test.dart`). Write the test, run it.

- [ ] **Step 5: Verify**

Run: `flutter test test/return_migration_test.dart` — PASS. `flutter analyze` — clean.
`flutter test` — full suite, no regressions.

- [ ] **Step 6: Commit**

```bash
git add lib/data/db/app_database.dart lib/data/db/app_database.g.dart test/return_migration_test.dart
git commit -m "feat: migrate schema to v3 — returns, return items, refund accounting"
```

---

### Task 2: Domain models and return calculation

**Files:**
- Modify: `lib/domain/enums.dart`, `lib/domain/models.dart`
- Create: `lib/domain/return_calculator.dart`
- Test: `test/return_calculator_test.dart`

- [ ] **Step 1: Add `CashEventType.refund`**

In `lib/domain/enums.dart`, add `refund` to the `CashEventType` enum (after `payOut`).
The `fromName`/`fromNameOrNull` helpers cover it automatically.

- [ ] **Step 2: Add models**

In `lib/domain/models.dart`, add immutable classes (matching the existing model style,
`==`/`hashCode` over all fields):
- `ReturnLineDraft` — `saleItemId, productId, nameSnapshot, unitPrice, taxRate (double),
  soldQty, alreadyReturnedQty, selectedQty`. Computed getters: `returnableQty =
  soldQty - alreadyReturnedQty`; `lineSubtotal = unitPrice * selectedQty`;
  `lineTax = (lineSubtotal * taxRate).round()`; `lineTotal = lineSubtotal + lineTax`.
  A `copyWith({int? selectedQty})`.
- `ReturnDraft` — `originalSaleId, originalReference, lines (List<ReturnLineDraft>),
  reason`. Computed `refundTotal` (sum of selected lines' `lineTotal`); `hasSelection`
  (any line with `selectedQty > 0`). Wrap `lines` with `List.unmodifiable` in the
  constructor (non-const), like `SaleRecord`.
- `ReturnLine` — persisted: `id, returnId, saleItemId, productId, nameSnapshot, qty,
  unitPrice, taxRate, lineTax, lineTotal`.
- `ReturnRecord` — persisted: `id, referenceNo, originalSaleId, cashierId, shiftId
  (nullable), reason, refundTotal, approvedBy, createdAt, lines (List<ReturnLine>)`.
  Wrap `lines` with `List.unmodifiable`.

- [ ] **Step 3: Write the failing return-calculator test**

`test/return_calculator_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/domain/return_calculator.dart';

void main() {
  test('refundForLine computes subtotal + rounded tax', () {
    expect(refundForLine(unitPrice: 100, qty: 2, taxRate: 0.0), 200);
    expect(refundForLine(unitPrice: 199, qty: 1, taxRate: 0.16), 231);
    expect(refundForLine(unitPrice: 100, qty: 3, taxRate: 0.16), 348);
  });

  test('refundTotal sums selected line refunds', () {
    expect(
      refundTotal([
        (unitPrice: 100, qty: 2, taxRate: 0.0),
        (unitPrice: 199, qty: 1, taxRate: 0.16),
      ]),
      431,
    );
    expect(refundTotal([]), 0);
  });
}
```

- [ ] **Step 4: Run it, watch it fail**

Run: `flutter test test/return_calculator_test.dart` — FAIL (file missing).

- [ ] **Step 5: Implement `lib/domain/return_calculator.dart`**

Pure Dart, no imports. `refundForLine` returns `unitPrice*qty + (unitPrice*qty*taxRate)
.round()`. `refundTotal` takes a `List<({int unitPrice, int qty, double taxRate})>` and
sums `refundForLine` over it. Document that tax is rounded per line (consistent with the
original sale's line-tax rounding).

- [ ] **Step 6: Verify**

Run: `flutter test test/return_calculator_test.dart` — PASS. `flutter analyze` — clean.

- [ ] **Step 7: Commit**

```bash
git add lib/domain/ test/return_calculator_test.dart
git commit -m "feat: add return domain models and refund calculation"
```

---

### Task 3: Return repository

**Files:**
- Create: `lib/data/repositories/return_repository.dart`
- Test: `test/return_repository_test.dart`

- [ ] **Step 1: Write the failing tests**

`test/return_repository_test.dart` — in-memory `AppDatabase` + `seedIfEmpty`. In `setUp`,
open a shift and complete a cash sale (via `SaleRepository`) so there is a sale to
return. Tests:
- `findSaleForReturn(referenceNo)` returns a draft-able view: the sale and, per line, its
  `soldQty`, `alreadyReturnedQty` (0 initially), and `returnableQty`. An unknown
  reference returns `null` (or a typed not-found result — your choice, be consistent).
- `recordReturn(...)` for a partial return: writes a `returns` row (with a
  `RET-YYYYMMDD-NNNN` reference), `return_items` rows, a refund `payments` row (negative
  `amount`, `method 'cash'`, `returnId` set), `stock_movements` rows (`type 'return'`,
  positive `qtyDelta`), a `refund` `cash_events` row, and increments the shift's
  `refundTotal` — all atomically. Product stock increases by the returned quantity.
- After a partial return, `findSaleForReturn` reflects the new `alreadyReturnedQty` and
  reduced `returnableQty`.
- `recordReturn` throws `OverReturnException` if a requested line quantity exceeds the
  current returnable quantity (guard re-checked inside the transaction).
- Return references increment per day (`RET-<today>-0001`, `-0002`).

- [ ] **Step 2: Run, watch fail**

Run: `flutter test test/return_repository_test.dart` — FAIL.

- [ ] **Step 3: Implement `lib/data/repositories/return_repository.dart`**

`ReturnRepository(AppDatabase db)`. Define `class OverReturnException implements
Exception`. Public methods return domain models.
- `findSaleForReturn(String referenceNo)` — load the sale + its `sale_items`; for each
  item compute `alreadyReturnedQty` = sum of `return_items.qty` referencing it; build a
  result the controller can turn into a `ReturnDraft`. Return null if no such sale.
- `recordReturn({required int originalSaleId, required int cashierId, required int
  shiftId, required String reason, required int approvedBy, required
  List<ReturnLineDraft> selectedLines})` — in ONE `db.transaction`: re-check each
  selected line's returnable quantity (throw `OverReturnException` on conflict);
  generate the `RET-` reference (sequential per day, same approach as
  `SaleRepository._nextReference` — read it for the pattern); insert the `returns` row;
  for each line insert a `return_items` row, add `qty` back to the product's `stock_qty`
  with an atomic SQL expression, and insert a `return` `stock_movements` row; insert one
  refund `payments` row (`amount = -refundTotal`, `method 'cash'`, `saleId =
  originalSaleId`, `returnId = <new>`); insert a `refund` `cash_events` row
  (`amount = refundTotal`); increment the shift's `refundTotal` by `refundTotal`. Return
  the persisted `ReturnRecord`.
- `getReturn(int id)` — load a `ReturnRecord` with its lines (for the receipt).

- [ ] **Step 4: Verify**

Run: `flutter test test/return_repository_test.dart` — PASS. `flutter analyze` — clean.
`flutter test` — full suite passes.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/return_repository.dart test/return_repository_test.dart
git commit -m "feat: add return repository with atomic refund recording"
```

---

### Task 4: Refund-aware shift and report accounting

**Files:**
- Modify: `lib/domain/shift_calculator.dart`, `lib/data/repositories/shift_repository.dart`,
  `lib/data/repositories/report_repository.dart`
- Test: `test/shift_calculator_test.dart` (extend), `test/return_repository_test.dart` (extend)

- [ ] **Step 1: Extend `expectedCash` with refunds**

In `lib/domain/shift_calculator.dart`, add a required `int refunds` parameter to
`expectedCash` so it returns `openingFloat + cashSales + payIn − payOut − refunds`.
Extend `test/shift_calculator_test.dart` with a case asserting refunds reduce expected
cash. Update EVERY caller of `expectedCash` (search `lib/` and `test/`): `shift_repository.dart`'s
`closeShift` must pass the shift's `refundTotal`; the end-shift screen's live
calculation must pass it too.

- [ ] **Step 2: Run the shift-calculator test**

Run: `flutter test test/shift_calculator_test.dart` — PASS after the implementation.

- [ ] **Step 3: Daily summary includes refunds**

In `lib/data/repositories/report_repository.dart`, extend `dailySummary` so the returned
`DailySummary` carries a returns count and a refund total for the day (sum of
`returns.refund_total` where `created_at` is within the day). Add `returnCount` and
`refundTotal` fields to the `DailySummary` model in `lib/domain/models.dart` (update its
`==`/`hashCode`); the existing `total`/`subtotal`/`taxTotal` keep their sale meaning.
Add a repository test asserting the refund total after a recorded return.

- [ ] **Step 4: Verify**

Run: `flutter test` — full suite passes. `flutter analyze` — clean.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/ lib/data/repositories/ test/
git commit -m "feat: account for refunds in expected cash and the daily summary"
```

---

### Task 5: Providers and return controller

**Files:**
- Modify: `lib/providers.dart`
- Create: `lib/features/returns/return_controller.dart`

- [ ] **Step 1: Add the provider**

In `lib/providers.dart` add `returnRepositoryProvider` (a `Provider<ReturnRepository>`
watching `databaseProvider`), mirroring the other repository providers.

- [ ] **Step 2: Build the return controller**

`lib/features/returns/return_controller.dart` — a Riverpod controller holding the
in-memory `ReturnDraft?` for the current return in progress. Methods: `loadSale(String
referenceNo)` (calls `ReturnRepository.findSaleForReturn`, builds a `ReturnDraft` with
all `selectedQty` 0, or surfaces not-found), `setLineQty(saleItemId, qty)` (clamped to
that line's `returnableQty`), `setReason(String)`, `clear()`. Expose the draft as state
(an `AsyncValue` or a `StateNotifier<ReturnDraft?>` — match the style of
`cart_controller.dart` / `shift_controller.dart`).

- [ ] **Step 3: Verify**

Run: `flutter analyze` — clean. `flutter test` — full suite passes.

- [ ] **Step 4: Commit**

```bash
git add lib/providers.dart lib/features/returns/return_controller.dart
git commit -m "feat: add return repository provider and return draft controller"
```

---

### Task 6: Returns screens and receipt

**Files:**
- Create: `lib/features/returns/returns_lookup_screen.dart`,
  `return_select_screen.dart`, `return_receipt.dart`
- Test: `test/returns_flow_test.dart`

- [ ] **Step 1: Returns lookup screen**

`returns_lookup_screen.dart` — a reference-number field and a "Find sale" button.
On found, routes to the select screen; on not-found shows a clear inline message.

- [ ] **Step 2: Return select screen**

`return_select_screen.dart` — shows the original sale's lines; each line shows
sold/returnable quantities and a quantity stepper capped at `returnableQty` (fully
returned lines are shown disabled). A reason field. A live refund total. A "Record
return" button that: requires an open shift (block with a message if none); calls
`requestManagerApproval` (action `"Record return / cash refund"`); on approval calls
`ReturnRepository.recordReturn` with the approver id; on success shows the return
receipt. A cancelled approval aborts with nothing recorded.

- [ ] **Step 3: Return receipt**

`return_receipt.dart` — `showReturnReceiptDialog(BuildContext, ReturnRecord)`, an
on-screen receipt marked "RETURN / REFUND" showing the original sale reference, the
returned lines, and the refund total; plus a small pure `buildReturnReceiptPdf` and a
"Print / PDF" action, mirroring Slice 1's `receipt.dart`.

- [ ] **Step 4: Widget tests**

`test/returns_flow_test.dart` — desktop-viewport widget tests: lookup of an existing
sale shows its lines; lookup of an unknown reference shows the not-found message;
selecting a partial quantity and recording (with the manager-approval dialog) writes the
return and shows the receipt; the over-return guard is not reachable from the UI (the
stepper caps at returnable). Use the in-memory-DB + seed + open-shift + completed-sale
setup pattern.

- [ ] **Step 5: Verify**

Run: `flutter test` — full suite passes. `flutter analyze` — clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/returns/ test/returns_flow_test.dart
git commit -m "feat: add returns lookup, selection, and return receipt screens"
```

---

### Task 7: Navigation and daily-summary wiring

**Files:**
- Modify: `lib/features/home_shell.dart`, `lib/features/reports/daily_summary_screen.dart`

- [ ] **Step 1: Returns rail destination**

In `lib/features/home_shell.dart` add a "Returns" `NavigationRail` destination that
opens the returns lookup screen. Place it after "Sell". It is available to all roles
(the manager-approval gate, not role-gating, controls who can finalise a refund).

- [ ] **Step 2: Daily summary shows refunds**

In `lib/features/reports/daily_summary_screen.dart` add rows for the returns count and
refund total (the `DailySummary` model now carries them), shown below the sales figures.

- [ ] **Step 3: Verify**

Run: `flutter test` — full suite passes. `flutter analyze` — clean.

- [ ] **Step 4: Commit**

```bash
git add lib/features/home_shell.dart lib/features/reports/daily_summary_screen.dart
git commit -m "feat: add Returns navigation and refund figures on the daily summary"
```

---

### Task 8: Final verification

**Files:** none — verification only.

- [ ] **Step 1: Full analyze + test**

Run: `flutter analyze` — `No issues found!`. `flutter test` — all pass; record the count.

- [ ] **Step 2: Spec coverage self-check**

Confirm against `docs/superpowers/specs/2026-05-16-highbridpos-slice3-design.md` that
every in-scope item is implemented: sale lookup; partial/full selection with returnable
caps; return reason; manager approval; cash refund; restock; atomic recording; return
receipt; refund-aware expected cash; daily-summary refunds; the v2→v3 migration.

- [ ] **Step 3: Final commit**

```bash
git commit --allow-empty -m "chore: HighbridPOS Slice 3 complete"
```

---

## Self-Review Notes

**Spec coverage** — sale lookup + returnable qty (Tasks 3, 6); partial/full selection
(Tasks 2, 5, 6); return reason (Tasks 2, 5, 6); manager approval (Task 6, reusing Slice 2's
`requestManagerApproval`); cash refund + atomic recording (Task 3); restock (Task 3);
return reference sequencing (Task 3); refund-aware expected cash (Task 4); daily-summary
refunds (Tasks 4, 7); return receipt (Task 6); v2→v3 migration (Task 1).

**Type consistency** — `CashEventType.refund` (Task 2) used by the return repository
(Task 3). `ReturnLineDraft`/`ReturnDraft`/`ReturnRecord`/`ReturnLine` defined in Task 2,
used by Tasks 3, 5, 6. `expectedCash` gains a `refunds` param in Task 4 — ALL callers
(`shift_repository.closeShift`, the end-shift screen) updated in the same task.
`DailySummary` gains `returnCount`/`refundTotal` in Task 4 — the daily-summary screen
(Task 7) reads them.

**Migration risk** — `returns.reference_no` is a plain `text()` column with uniqueness
enforced by an index created in both `onCreate` and `onUpgrade`, so created-v3 and
upgraded-v3 are identical. The migration test (Task 1) is the guard.
