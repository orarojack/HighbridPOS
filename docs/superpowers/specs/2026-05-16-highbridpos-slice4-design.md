# HighbridPOS — Slice 4 Design

**Date:** 2026-05-16
**Status:** Approved

## Context

Slices 1–3 delivered the cash POS, PIN login + shifts + cash drawer, and returns &
refunds. Every sale so far rings up at the product's full price.

**Slice 4** adds **line-item discounts** — the cashier can knock a fixed amount or a
percentage off any cart line, with manager approval required once a discount crosses a
configurable threshold. Discounts flow correctly through tax, the recorded sale, the
receipt, and the daily summary.

Still a single terminal, still no backend. Same Flutter app, same local SQLite database,
extended by a schema migration to version 4.

## Scope

### In scope

- **Per-line discount.** Any cart line can carry a discount entered as either a fixed
  cash amount or a percentage of the line subtotal. The line's tax and total recompute
  from the discounted (net) amount.
- **Manager approval threshold.** A discount whose percentage of the line subtotal is at
  or above a threshold (default 15%) requires manager/admin approval (reuses
  `requestManagerApproval`). Below the threshold a cashier may apply it directly.
- **Discount on the sale record.** Each `sale_item` stores the discount applied; the
  `sale` stores the discount total. The receipt shows the per-line discount and the
  total saved.
- **Reporting.** The daily summary gains a discount total for the day.
- **Stock & money integrity unchanged.** Discounts only reduce the charged amount; stock
  deduction, the single-transaction sale, and returns all keep working — a return
  refunds the discounted line total, not the full price.

### Explicitly deferred (later slices)

Whole-cart / order-level discounts; scheduled promotions with start/end dates; coupon
codes; buy-one-get-one and bundle pricing; customer-group and loyalty discounts; staff
discounts; the promotions-rules engine. Slice 4 is manual, per-line discounts only.

## Technology

Unchanged: Flutter Desktop, drift (SQLite), Riverpod, bcrypt, pdf + printing,
build_runner. No new packages.

## Architecture

Same layering. Slice 4's main change is to the **pure sale-calculation domain logic**
(`sale_calculator.dart` / the `CartLine` model) — discounts must be modelled there so
tax is computed on the net amount and the logic stays unit-tested. Slice 4 adds:

- `domain/` — `CartLine` gains a discount; `sale_calculator` computes net/tax/total with
  discounts; a small discount-resolution helper turns an amount-or-percentage entry into
  a clamped cent value.
- `data/repositories/` — `SaleRepository.completeCashSale` persists per-line discounts
  and the sale discount total; `ReturnRepository` already snapshots `unit_price`/`qty`
  per line — it must also snapshot the line discount so refunds match what was charged.
- `features/pos/` — a discount dialog on each cart line; the cart and totals show
  discounts.
- `report_repository` / the daily summary surface the discount total.

The repository seam is preserved.

## Data model (Slice 4 — schema version 4)

A drift migration upgrades `schemaVersion` 3 → 4.

### Changed tables

- **sale_items** — add `discount` (int, default 0; cents taken off this line's
  subtotal).
- **sales** — add `discount_total` (int, default 0; sum of line discounts).
- **return_items** — add `discount` (int, default 0); a returned line snapshots the
  discount that was on the original `sale_item` so the refund equals the discounted
  amount actually charged.

No new tables. All money stays integer minor units (cents).

## Behaviour decisions

- **Discount entry:** the cashier picks "Amount" or "Percent". An amount is a cent value;
  a percent (0–100) is converted to cents = `round(lineSubtotal × percent / 100)`. The
  resulting discount is clamped to `[0, lineSubtotal]` — a discount can never exceed the
  line subtotal or make a line negative.
- **Line math with a discount:** `lineSubtotal = unitPrice × qty`;
  `lineDiscount` (clamped cents); `lineNet = lineSubtotal − lineDiscount`;
  `lineTax = round(lineNet × taxRate)`; `lineTotal = lineNet + lineTax`. Tax is charged
  on the discounted amount.
- **Cart totals:** `subtotal` = Σ `lineSubtotal` (pre-discount, gross);
  `discountTotal` = Σ `lineDiscount`; `taxTotal` = Σ `lineTax`;
  `total` = Σ `lineTotal` = `subtotal − discountTotal + taxTotal`.
- **Approval threshold:** the discount percentage of a line = `lineDiscount /
  lineSubtotal`. At or above 15% it needs manager approval before it is applied to the
  cart line. The threshold is a single named constant (later slices may make it a
  setting).
- **Changing quantity after a discount:** if a line already has a *percentage* discount
  and its quantity changes, the discount is **not** auto-recomputed in Slice 4 — the
  applied cent discount stays, re-clamped to the new (possibly smaller) subtotal. The
  cashier can re-open the discount dialog to adjust. (Keeps the cart model simple;
  documented so it is a deliberate choice, not a bug.)
- **Receipt:** each discounted line shows its discount; the receipt shows a
  "Discount" total line when `discountTotal > 0`.
- **Returns:** a returned line refunds `lineNet + lineTax` based on the snapshotted
  discounted `unit_price`/`discount`, so a customer is refunded what they actually paid.
- **Stock unaffected:** discounts touch money only; quantities and stock movements are
  unchanged.

## Error handling

- The discount dialog validates: amount ≥ 0 and ≤ line subtotal; percent in 0–100. An
  invalid entry is blocked with an inline message; the dialog cannot apply an
  out-of-range discount.
- A discount needing approval that is cancelled at the approval dialog leaves the line
  unchanged.
- Sale completion stays atomic; persisting discounts adds no new failure mode.

## Testing

- **Pure-Dart unit tests** for the discounted sale calculation: line net/tax/total with
  a fixed-amount discount and with a percentage discount; cart subtotal/discountTotal/
  taxTotal/total; clamping (discount capped at the subtotal); the discount-percentage
  and approval-threshold helper.
- **Repository tests** against in-memory SQLite: the v3→v4 migration; `completeCashSale`
  persists per-line `discount` and the sale `discount_total`; a return of a discounted
  line refunds the discounted amount; the daily summary discount total.
- **Widget tests:** applying a fixed and a percentage discount to a cart line; the cart
  and totals reflecting the discount; the manager-approval gate firing for an
  above-threshold discount and not for a below-threshold one.

## Out-of-scope reminders

No network, no backend, single terminal. Per-line manual discounts only — no cart-level
discounts, no promotions engine, no coupons. Slice 4 only lets a cashier discount
individual cart lines, correctly and accountably.
