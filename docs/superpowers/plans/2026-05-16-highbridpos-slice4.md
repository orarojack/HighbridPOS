# HighbridPOS Slice 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-line discounts (fixed amount or percentage, with a manager-approval threshold) to the HighbridPOS desktop POS — flowing correctly through tax, the recorded sale, returns, the receipt, and the daily summary.

**Architecture:** Same layered Flutter app. Slice 4's core change is the pure sale-calculation domain logic: a cart line carries a discount, and tax is computed on the discounted (net) amount. A schema migration to v4 persists discounts on `sale_items`/`sales`/`return_items`. The repository seam is preserved.

**Tech Stack:** Flutter Desktop, drift (SQLite), Riverpod, bcrypt, pdf + printing, build_runner. No new packages.

---

## Prerequisite

Slices 1–3 are complete; Slice 4 is built on branch `slice4-discounts` (off
`slice3-returns`). Flutter SDK 3.41.9 at `~/flutter`, on `PATH` via `~/.bashrc`.
Verification is `flutter analyze` + `flutter test`.

Design spec: `docs/superpowers/specs/2026-05-16-highbridpos-slice4-design.md`.

## Conventions carried from Slices 1–3

- Money is integer minor units (cents): `int`. Tax is rounded per line.
- drift migrations: SQLite cannot `ADD COLUMN` with a UNIQUE constraint (not an issue
  here — the new columns are plain integers with defaults).
- Domain models immutable, `final` fields, `==`/`hashCode` over all fields;
  `models.dart` imports only `enums.dart`.
- Repositories take `AppDatabase`, return domain models via `_toX` mappers, wrap
  multi-write ops in `db.transaction`.
- Widget tests: desktop viewport helper (1400×900), in-memory `AppDatabase` +
  `seedIfEmpty`, `ProviderScope` overrides. Some widget tests need an open shift before
  the Sell screen is usable (Slice 2 gating) — follow `test/sale_screen_test.dart`.
- `flutter analyze` stays clean. TDD: failing test → fail → implement → pass → commit.

## Discount math (the contract every task must follow)

For a cart line with `unitPrice`, `qty`, `taxRate`, and a discount in cents:
```
lineSubtotal = unitPrice * qty                 // gross, pre-discount
lineDiscount = discount.clamp(0, lineSubtotal)  // never exceeds the subtotal
lineNet      = lineSubtotal - lineDiscount
lineTax      = (lineNet * taxRate).round()      // tax on the discounted amount
lineTotal    = lineNet + lineTax
```
Cart totals: `subtotal = Σ lineSubtotal` (gross); `discountTotal = Σ lineDiscount`;
`taxTotal = Σ lineTax`; `total = Σ lineTotal` ( = `subtotal − discountTotal + taxTotal`).

Resolving a discount entry to cents: a percentage `p` (0–100) of a line →
`(lineSubtotal * p / 100).round()`, then clamp to `[0, lineSubtotal]`; a fixed amount →
the cent value, clamped to `[0, lineSubtotal]`.

Approval: `discountFraction = lineDiscount / lineSubtotal` (0 when subtotal is 0).
A discount with `discountFraction >= kDiscountApprovalThreshold` (0.15) needs manager
approval before being applied.

## File Structure

```
lib/data/db/app_database.dart        MODIFY — sale_items.discount, sales.discountTotal, return_items.discount; schemaVersion 4 + onUpgrade
lib/domain/models.dart               MODIFY — CartLine.discount; CartTotals.discountTotal; ReturnLineDraft discount; DailySummary.discountTotal
lib/domain/sale_calculator.dart      MODIFY — calculateTotals with discounts
lib/domain/discount_calculator.dart  CREATE — resolveDiscount + discountNeedsApproval + kDiscountApprovalThreshold
lib/domain/return_calculator.dart    MODIFY — refundForLine accounts for a discount
lib/data/repositories/sale_repository.dart    MODIFY — persist per-line discount + sale discountTotal
lib/data/repositories/return_repository.dart  MODIFY — snapshot proportional line discount; refund the discounted amount
lib/data/repositories/report_repository.dart  MODIFY — dailySummary discount total
lib/features/pos/cart_controller.dart         MODIFY — setLineDiscount
lib/features/pos/discount_dialog.dart         CREATE — amount/percent discount entry dialog
lib/features/pos/sale_screen.dart    MODIFY — per-line discount action; cart + totals show discounts
lib/features/pos/receipt.dart        MODIFY — show line discounts + a Discount total line
lib/features/reports/daily_summary_screen.dart  MODIFY — show the discount total
test/discount_calculator_test.dart   CREATE
test/sale_calculator_test.dart       MODIFY — discounted-cart cases
test/discount_migration_test.dart    CREATE
test/discount_repository_test.dart   CREATE
test/discount_flow_test.dart         CREATE
```

---

### Task 1: Schema migration to version 4

**Files:**
- Modify: `lib/data/db/app_database.dart`
- Generated: `lib/data/db/app_database.g.dart`
- Test: `test/discount_migration_test.dart`

- [ ] **Step 1: Add the columns**

In `lib/data/db/app_database.dart`:
- `SaleItems` table — add `IntColumn get discount => integer().withDefault(const Constant(0))();`
- `Sales` table — add `IntColumn get discountTotal => integer().withDefault(const Constant(0))();`
- `ReturnItems` table — add `IntColumn get discount => integer().withDefault(const Constant(0))();`

- [ ] **Step 2: schemaVersion 4 + onUpgrade**

Bump `schemaVersion` to `4`. In `MigrationStrategy.onUpgrade`, after the existing
`from < 3` block, add:
```dart
if (from < 4) {
  await m.addColumn(saleItems, saleItems.discount);
  await m.addColumn(sales, sales.discountTotal);
  await m.addColumn(returnItems, returnItems.discount);
}
```
All three are plain integer columns with a default, so `addColumn` is safe (no UNIQUE).
Note for a chained upgrade: the `from < 3` block calls `m.createTable(returnItems)`,
which builds `return_items` from the current v4 schema (already including `discount`);
guard the `addColumn(returnItems, ...)` with `if (from >= 3)` so a chained v1/v2→v4
upgrade does not duplicate the column. `sale_items` and `sales` exist since v1, so their
`addColumn`s stay unconditional.

- [ ] **Step 3: Regenerate**

Run: `dart run build_runner build` (generous timeout). Confirm it regenerates cleanly.

- [ ] **Step 4: Migration test**

`test/discount_migration_test.dart` — assert a fresh v4 DB has `sale_items.discount`,
`sales.discount_total`, `return_items.discount`, and `schemaVersion == 4`; and a v3→v4
upgrade preserves data. Follow `test/return_migration_test.dart`.

- [ ] **Step 5: Verify**

Run: `flutter test test/discount_migration_test.dart` — PASS. `flutter analyze` — clean.
`flutter test` — full suite, no regressions.

- [ ] **Step 6: Commit**

```bash
git add lib/data/db/app_database.dart lib/data/db/app_database.g.dart test/discount_migration_test.dart
git commit -m "feat: migrate schema to v4 — per-line and per-sale discounts"
```

---

### Task 2: Discount domain logic

**Files:**
- Modify: `lib/domain/models.dart`, `lib/domain/sale_calculator.dart`
- Create: `lib/domain/discount_calculator.dart`
- Test: `test/discount_calculator_test.dart`, `test/sale_calculator_test.dart`

- [ ] **Step 1: Extend `CartLine` and `CartTotals`**

In `lib/domain/models.dart`:
- `CartLine` — add `final int discount;` (default `0` in the constructor). Update the
  computed getters to the discount math contract above: keep `lineSubtotal = unitPrice *
  qty`; add `lineDiscount` (clamped), `lineNet`; change `lineTax` to
  `(lineNet * product.taxRate).round()`; `lineTotal = lineNet + lineTax`. Extend
  `copyWith` to `copyWith({int? qty, int? discount})`. Update `==`/`hashCode` to include
  `discount`.
- `CartTotals` — add `final int discountTotal;`. Update the constructor, `CartTotals.empty`
  (discountTotal 0), and `==`/`hashCode`.

- [ ] **Step 2: Update `sale_calculator.dart`**

`calculateTotals(List<CartLine>)` now also sums `discountTotal`. Returns a `CartTotals`
with `subtotal = Σ lineSubtotal`, `discountTotal = Σ lineDiscount`, `taxTotal = Σ lineTax`,
`total = Σ lineTotal`. `changeDue`/`isSufficientTender` are unchanged.

- [ ] **Step 3: Update `test/sale_calculator_test.dart`**

The existing tests construct `CartLine`s with no discount — they still pass (`discount`
defaults to 0). ADD cases: a line with a fixed-amount discount (e.g. unitPrice 200,
qty 2, taxRate 0.1, discount 100 → subtotal 400, net 300, tax 30, total 330); a cart
mixing a discounted and an undiscounted line, asserting `subtotal`, `discountTotal`,
`taxTotal`, `total`; a discount larger than the subtotal is clamped (line total never
negative, tax 0).

- [ ] **Step 4: Write the failing discount-calculator test**

`test/discount_calculator_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/domain/discount_calculator.dart';

void main() {
  test('resolveDiscount: fixed amount clamps to the subtotal', () {
    expect(resolveDiscount(lineSubtotal: 1000, isPercent: false, value: 250), 250);
    expect(resolveDiscount(lineSubtotal: 1000, isPercent: false, value: 5000), 1000);
    expect(resolveDiscount(lineSubtotal: 1000, isPercent: false, value: -5), 0);
  });

  test('resolveDiscount: percent of the subtotal, rounded and clamped', () {
    expect(resolveDiscount(lineSubtotal: 1000, isPercent: true, value: 10), 100);
    expect(resolveDiscount(lineSubtotal: 999, isPercent: true, value: 10), 100); // 99.9 -> 100
    expect(resolveDiscount(lineSubtotal: 1000, isPercent: true, value: 150), 1000);
    expect(resolveDiscount(lineSubtotal: 1000, isPercent: true, value: 0), 0);
  });

  test('discountNeedsApproval at or above the threshold', () {
    expect(discountNeedsApproval(lineDiscount: 100, lineSubtotal: 1000), false); // 10%
    expect(discountNeedsApproval(lineDiscount: 150, lineSubtotal: 1000), true);  // 15%
    expect(discountNeedsApproval(lineDiscount: 300, lineSubtotal: 1000), true);  // 30%
    expect(discountNeedsApproval(lineDiscount: 0, lineSubtotal: 0), false);
  });
}
```

- [ ] **Step 5: Run the tests, watch them fail**

Run: `flutter test test/discount_calculator_test.dart` — FAIL (file missing).

- [ ] **Step 6: Implement `lib/domain/discount_calculator.dart`**

Pure Dart, no imports.
```dart
/// A discount of this fraction of a line's subtotal (or more) needs manager approval.
const double kDiscountApprovalThreshold = 0.15;

/// Resolves a discount entry to a clamped cent value for a line.
/// [value] is a cent amount when [isPercent] is false, or a 0–100 percentage when true.
int resolveDiscount({
  required int lineSubtotal,
  required bool isPercent,
  required num value,
}) {
  if (lineSubtotal <= 0) return 0;
  final raw = isPercent
      ? (lineSubtotal * value / 100).round()
      : value.round();
  return raw.clamp(0, lineSubtotal);
}

/// True when a line discount is at or above the manager-approval threshold.
bool discountNeedsApproval({required int lineDiscount, required int lineSubtotal}) {
  if (lineSubtotal <= 0) return false;
  return lineDiscount / lineSubtotal >= kDiscountApprovalThreshold;
}
```

- [ ] **Step 7: Run all the tests**

Run: `flutter test test/discount_calculator_test.dart test/sale_calculator_test.dart` —
PASS. `flutter analyze` — clean. `flutter test` — full suite passes (the `CartTotals`
field addition may touch other tests/code — fix any caller that constructs `CartTotals`
directly; report which).

- [ ] **Step 8: Commit**

```bash
git add lib/domain/ test/discount_calculator_test.dart test/sale_calculator_test.dart
git commit -m "feat: add per-line discount calculation to the sale domain logic"
```

---

### Task 3: Persist discounts in sale and return repositories

**Files:**
- Modify: `lib/data/repositories/sale_repository.dart`,
  `lib/data/repositories/return_repository.dart`, `lib/domain/models.dart`,
  `lib/domain/return_calculator.dart`
- Test: `test/discount_repository_test.dart`

- [ ] **Step 1: Write the failing tests**

`test/discount_repository_test.dart` — in-memory `AppDatabase` + seed + open shift.
Tests:
- `completeCashSale` with a cart line carrying a discount writes the `sale_items.discount`
  and the `sales.discount_total`; the persisted `SaleRecord` lines/total reflect the
  discounted amounts. Use the discount math contract to compute expected values.
- A return of a discounted sale line refunds the DISCOUNTED amount: complete a sale with
  a discounted line, then `findSaleForReturn` + `recordReturn` a partial quantity, and
  assert the refund equals `unitPrice*returnQty − proportionalDiscount + tax` (see
  Step 4 for the proportional formula), NOT the full-price amount.
- The daily summary discount total (this can also be asserted here or in Task 4's tests).

- [ ] **Step 2: Run, watch fail**

Run: `flutter test test/discount_repository_test.dart` — FAIL.

- [ ] **Step 3: `SaleRepository.completeCashSale` persists discounts**

`completeCashSale` receives `List<CartLine>` (the cart). For each line, write
`SaleItemsCompanion.insert(... discount: Value(line.lineDiscount) ...)` and use the
line's discounted `lineTax`/`lineTotal` (the `CartLine` getters already compute them).
Compute the sale's `discountTotal = Σ line.lineDiscount` and write it onto the `sales`
row. The sale `subtotal`/`taxTotal`/`total` must come from `calculateTotals` so they are
consistent with the discount contract. `SaleLine` (domain) — add a `discount` field if
the receipt needs it (see Task 6); update its `==`/`hashCode` and the `_toSaleLine`
mapper to read `row.discount`.

- [ ] **Step 4: `ReturnRepository` snapshots the proportional line discount**

A `sale_item` now has a total `discount` spread over its `qty` units. When returning
`returnQty` of a line with sold `qty` and total `discount`:
```
proportionalDiscount = (discount * returnQty / qty).round()
lineSubtotal = unitPrice * returnQty
lineNet      = lineSubtotal - proportionalDiscount
lineTax      = (lineNet * taxRate).round()
lineTotal    = lineNet + lineTax        // the refund for this returned line
```
Changes:
- `ReturnLineDraft` (in `models.dart`) — add a `saleItemDiscount` field (the original
  sale_item's total discount) and a `saleItemQty` field if not already present (it has
  `soldQty` — reuse it). Update the computed getters so `lineDiscount` is the
  proportional discount for `selectedQty`, `lineNet`/`lineTax`/`lineTotal` follow the
  formula above. Update `==`/`hashCode`/`copyWith`.
- `return_calculator.dart` — `refundForLine` gains a discount parameter (the
  proportional line discount) and computes `unitPrice*qty − discount + tax`. Update
  `test/return_calculator_test.dart` accordingly.
- `ReturnRepository.findSaleForReturn` — populate `saleItemDiscount` from the
  `sale_items.discount` column.
- `ReturnRepository.recordReturn` — compute the proportional discount per returned line,
  store it in `return_items.discount`, and base the refund total on the discounted
  `lineTotal`. The `ReturnLine` domain model — add a `discount` field; update its
  `==`/`hashCode` and the mapper.

- [ ] **Step 5: Verify**

Run: `flutter test` — full suite passes. `flutter analyze` — clean.

- [ ] **Step 6: Commit**

```bash
git add lib/ test/discount_repository_test.dart test/return_calculator_test.dart
git commit -m "feat: persist line discounts in sales and refund discounted amounts on returns"
```

---

### Task 4: Discount total in the daily summary

**Files:**
- Modify: `lib/domain/models.dart`, `lib/data/repositories/report_repository.dart`
- Test: `test/discount_repository_test.dart` (extend) or `test/repositories_test.dart`

- [ ] **Step 1: Add `DailySummary.discountTotal`**

In `lib/domain/models.dart`, add `final int discountTotal;` to `DailySummary` (update
the constructor and `==`/`hashCode`). It is the sum of `sales.discount_total` for the
day.

- [ ] **Step 2: Compute it in `dailySummary`**

In `lib/data/repositories/report_repository.dart`, extend `dailySummary` to sum
`sales.discount_total` over the same day window and populate `discountTotal`. Add a test
asserting it after a discounted sale. Update any existing `DailySummary(...)` construction
sites (the existing daily-summary tests) to pass `discountTotal`.

- [ ] **Step 3: Verify**

Run: `flutter test` — full suite passes. `flutter analyze` — clean.

- [ ] **Step 4: Commit**

```bash
git add lib/ test/
git commit -m "feat: include the day's discount total in the daily summary"
```

---

### Task 5: Cart discount controller and dialog

**Files:**
- Modify: `lib/features/pos/cart_controller.dart`
- Create: `lib/features/pos/discount_dialog.dart`

- [ ] **Step 1: `cart_controller.dart` — `setLineDiscount`**

Add `setLineDiscount(int productId, int discountCents)` to `CartController`: it replaces
the matching cart line via `copyWith(discount: ...)`. The caller (Task 6) passes a
discount already resolved to cents and already approved if needed. The controller
clamps nothing extra — `CartLine.lineDiscount` clamps for display/calc — but it should
store the raw cents passed.

- [ ] **Step 2: Build `discount_dialog.dart`**

`lib/features/pos/discount_dialog.dart` — `Future<int?> showDiscountDialog(BuildContext
context, {required int lineSubtotal, required int currentDiscount})`. A dialog with an
Amount/Percent toggle and a value field. On confirm it resolves the entry to cents with
`resolveDiscount` and returns the cent value (`null` on cancel). It validates the entry
(amount ≥ 0; percent 0–100) and shows an inline error for an out-of-range value. The
dialog itself does NOT do the approval check — it just returns the resolved cents; the
Sell screen (Task 6) decides whether approval is needed and gates it. Match the dialog
style of `payment_dialog.dart` / `manager_approval.dart`.

- [ ] **Step 3: Verify**

Run: `flutter analyze` — clean. `flutter test` — full suite passes.

- [ ] **Step 4: Commit**

```bash
git add lib/features/pos/cart_controller.dart lib/features/pos/discount_dialog.dart
git commit -m "feat: add cart line-discount controller method and discount entry dialog"
```

---

### Task 6: Sell screen and receipt show discounts

**Files:**
- Modify: `lib/features/pos/sale_screen.dart`, `lib/features/pos/receipt.dart`,
  `lib/features/reports/daily_summary_screen.dart`
- Test: `test/discount_flow_test.dart`

- [ ] **Step 1: Per-line discount action on the Sell screen**

In `lib/features/pos/sale_screen.dart`, each cart line (`_CartTile`) gets a "Discount"
action that opens `showDiscountDialog` with that line's `lineSubtotal` and current
`discount`. When the dialog returns a cent value: if `discountNeedsApproval(lineDiscount:
resolved, lineSubtotal: lineSubtotal)` is true, call `requestManagerApproval(action:
"Apply discount")` first — on a non-null approver apply it via
`cartController.setLineDiscount`, on cancel leave the line unchanged; if approval is not
needed, apply it directly. A discounted line shows its discount and discounted total.

- [ ] **Step 2: Totals panel shows the discount**

The `_TotalsPanel` shows a "Discount" row (the cart `discountTotal`) when it is greater
than zero, between Subtotal and Tax.

- [ ] **Step 3: Receipt shows discounts**

In `lib/features/pos/receipt.dart`, each discounted line shows its discount, and the
receipt shows a "Discount" total line when the sale's discount total > 0 — on-screen
and in the PDF.

- [ ] **Step 4: Daily summary shows the discount total**

In `lib/features/reports/daily_summary_screen.dart`, add a "Discounts given" row showing
`s.discountTotal` (via `formatMoney`).

- [ ] **Step 5: Widget tests**

`test/discount_flow_test.dart` — desktop-viewport widget tests (open a shift first):
applying a small fixed discount to a cart line updates the cart total and the Discount
row, no approval dialog; applying an above-threshold percentage discount triggers the
manager-approval dialog and applies only after approval; cancelling the approval leaves
the line at its previous discount.

- [ ] **Step 6: Verify**

Run: `flutter test` — full suite passes. `flutter analyze` — clean. If a golden
screenshot (`doc/preview/04-sell-active.png`) legitimately changed, regenerate it with
`flutter test --update-goldens test/screenshots_test.dart` and note it.

- [ ] **Step 7: Commit**

```bash
git add lib/features/ test/discount_flow_test.dart doc/preview
git commit -m "feat: apply line discounts on the Sell screen with the receipt and summary"
```

---

### Task 7: Final verification

**Files:** none — verification only.

- [ ] **Step 1: Full analyze + test**

Run: `flutter analyze` — `No issues found!`. `flutter test` — all pass; record the count.

- [ ] **Step 2: Spec coverage self-check**

Confirm against `docs/superpowers/specs/2026-05-16-highbridpos-slice4-design.md` that
every in-scope item is implemented: per-line amount/percent discount; tax on the net
amount; the 15% approval threshold; discount on the sale record and receipt; returns
refunding the discounted amount; the daily-summary discount total; the v3→v4 migration.

- [ ] **Step 3: Final commit**

```bash
git commit --allow-empty -m "chore: HighbridPOS Slice 4 complete"
```

---

## Self-Review Notes

**Spec coverage** — per-line discount math (Task 2); amount/percent entry + clamping
(Tasks 2, 5); 15% approval threshold (Tasks 2, 6); discount persisted on sale_items/sales
(Task 3); returns refunding the discounted (proportional) amount (Task 3); daily-summary
discount total (Tasks 4, 6); v3→v4 migration (Task 1); receipt discounts (Task 6).

**Type consistency** — `CartLine.discount` and `CartTotals.discountTotal` (Task 2) are
read by `sale_calculator` (Task 2), `SaleRepository` (Task 3), and the Sell screen
(Task 6). `CartTotals` gains a field in Task 2 — all direct constructors updated then.
`DailySummary.discountTotal` (Task 4) read by the daily-summary screen (Task 6).
`SaleLine.discount` and `ReturnLine.discount` / `ReturnLineDraft.saleItemDiscount`
(Task 3) — added with their mappers in the same task.

**Migration risk** — three plain integer columns with defaults; `addColumn` is safe. The
`returnItems.discount` `addColumn` is guarded `if (from >= 3)` so a chained upgrade
(whose `from < 3` block recreates `return_items` already in v4 shape) does not duplicate
it. The migration test (Task 1) is the guard.
