# HighbridPOS — Slice 3 Design

**Date:** 2026-05-16
**Status:** Approved

## Context

Slice 1 delivered the single-terminal cash POS (login, products, cash-sale loop,
receipts, daily summary). Slice 2 added Staff ID + PIN login, shift management, the cash
drawer, and a reusable manager-approval mechanism.

**Slice 3** adds **returns and refunds** — the controlled reversal of a completed sale.
A supermarket must be able to take goods back, refund the customer in cash, put the
stock back, and keep the cash drawer and reports honest. Returns are sensitive, so every
refund goes through the Slice 2 manager-approval gate.

Still a single terminal, still no backend. Same Flutter app, same local SQLite database,
extended by a schema migration to version 3.

## Scope

### In scope

- **Find a sale.** A returns screen looks up a completed sale by its reference number
  (`YYYYMMDD-NNNN`) and shows its line items.
- **Select what to return.** Full or partial return — choose line items and a quantity
  per line, up to what remains un-returned on that line (a line can be returned across
  several separate returns).
- **Return reason.** A free-text reason captured per return.
- **Manager approval.** Recording a return/refund requires manager/admin approval
  (reuses `requestManagerApproval`); the approver is stored on the return.
- **Cash refund.** The refund amount is the sum of the returned lines (unit price × qty
  + line tax). Slice 3 refunds in cash only.
- **Restock.** Returned quantities are added back to product stock with a `return`
  stock movement.
- **Atomic recording.** A return writes `returns` + `return_items` + a refund
  `payment` + `stock_movements` + a `refund` cash event, and updates the shift's refund
  total — all in one transaction.
- **Return receipt.** On-screen + PDF, marked as a return, showing the original sale
  reference and the refunded lines.
- **Reporting.** The daily summary gains a returns count and refund total; the shift's
  expected cash subtracts refunds.

### Explicitly deferred (later slices)

Exchanges (return-and-rebuy in one step); non-cash refunds (card / mobile money / store
credit); restocking fees; distinct damaged-vs-expired return workflows beyond the reason
text; discounts & promotions; suppliers & purchasing; multi-terminal; the backend.

## Technology

Unchanged: Flutter Desktop, drift (SQLite), Riverpod, bcrypt, pdf + printing,
build_runner. No new packages.

## Architecture

Same layering. Slice 3 adds:

- `domain/` — `ReturnDraft` / `ReturnLineDraft` (in-memory selection), `ReturnRecord` /
  `ReturnLine` (persisted), and pure return-calculation functions (refund total from
  selected lines), unit-tested.
- `data/repositories/` — `return_repository.dart`: sale lookup with per-line returnable
  quantity, and atomic return recording.
- `features/returns/` — the returns lookup + selection + confirmation screens, and the
  return receipt.
- The Sell screen / home shell gain a "Returns" entry point.

The repository seam is preserved.

## Data model (Slice 3 — schema version 3)

A drift migration upgrades `schemaVersion` 2 → 3.

### New tables

- **returns** — `id, reference_no (unique, 'RET-YYYYMMDD-NNNN'), original_sale_id
  (FK sales), cashier_id (FK users), shift_id (FK shifts, nullable), reason,
  refund_total, approved_by (FK users), created_at`
- **return_items** — `id, return_id (FK returns), sale_item_id (FK sale_items),
  product_id (FK products), name_snapshot, qty, unit_price, tax_rate, line_tax,
  line_total`

### Changed tables

- **payments** — add `return_id` (int, FK → returns, nullable). A refund is a `payments`
  row with a negative `amount`, `method = 'cash'`, `return_id` set, and `sale_id` left
  as the original sale id for traceability.
- **shifts** — add `refund_total` (int, default 0).

`CashEventType` gains a `refund` value (a stored string — no schema change to the
`cash_events` table, which already has a free-text `type` column).

All money stays integer minor units (cents).

## Behaviour decisions

- **Return reference:** `RET-YYYYMMDD-NNNN`, sequential per calendar day, generated the
  same way as sale references.
- **Returnable quantity:** for each `sale_item`, returnable = `qty − Σ(return_items.qty
  referencing it)`. The selection UI caps each line at its returnable quantity; a fully
  returned line shows as such and cannot be selected.
- **Refund amount:** per returned line, `unit_price × qty` rounded to the line tax the
  same way the original sale computed it (`line_tax = round(line_subtotal × tax_rate)`);
  refund total = Σ line totals. Returned lines snapshot the original `unit_price` and
  `tax_rate` from the `sale_item`, so price changes after the sale never affect a refund.
- **Cash drawer:** a cash refund reduces drawer cash. Recording a return writes a
  `refund` cash event and adds to the shift's `refund_total`. Expected cash becomes
  `opening_float + cash_sales + pay_in − pay_out − refunds`.
- **Shift requirement:** like selling, recording a return requires an open shift for the
  signed-in user (the refund must land in a shift's drawer accounting). The return is
  linked to that shift.
- **Stock:** each returned line adds `qty` back to `products.stock_qty` and writes a
  `stock_movements` row with `type = 'return'`, `qty_delta = +qty`, `ref_type =
  'return'`, `ref_id = return.id`.
- **No double refund:** the returnable-quantity guard is re-checked inside the recording
  transaction; if a line's returnable quantity changed, the transaction fails and nothing
  is recorded.
- **Approval:** the manager-approval dialog is shown before the recording transaction;
  the approving user's id is stored as `returns.approved_by`. A cancelled approval
  aborts the return with nothing recorded.

## Error handling

- Sale lookup: an unknown or malformed reference number gives a clear inline message.
- A sale with every line fully returned shows "Nothing left to return".
- The recording transaction is atomic; on any failure (including a returnable-quantity
  conflict) nothing is recorded and the draft is preserved with an error surfaced.
- Recording a return with no open shift is blocked with an explanatory message.

## Testing

- **Pure-Dart unit tests** for return calculation: refund total from selected lines,
  per-line tax at minor-unit precision, partial quantities.
- **Repository tests** against in-memory SQLite: the v2→v3 migration; sale lookup with
  returnable quantities; recording a return (returns + return_items + refund payment +
  stock movements + refund cash event, stock restored, shift refund_total updated, all
  atomic); the over-return guard (cannot return more than remains); return-reference
  sequencing; daily summary including refunds.
- **Widget tests:** the returns lookup (found / not found), selecting partial
  quantities, the manager-approval gate on recording, and a completed return showing the
  return receipt.

## Out-of-scope reminders

No network, no backend, single terminal. Cash refunds only. Exchanges, non-cash refunds,
and discounts remain deferred — Slice 3 only adds the controlled reversal of a cash sale.
