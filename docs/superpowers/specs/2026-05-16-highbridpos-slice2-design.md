# HighbridPOS — Slice 2 Design

**Date:** 2026-05-16
**Status:** Approved

## Context

Slice 1 delivered a working single-terminal Flutter desktop POS: username/password
login with roles, product management, the cash-sale loop with stock deduction, receipts,
and a daily summary — all on a local drift/SQLite database, no backend.

**Slice 2** completes the section-47 MVP of the master plan for a single till by adding
the three things Slice 1 deliberately skipped: **Staff ID + PIN login**, **cashier shift
management**, and **cash-drawer control**. It also introduces a reusable **manager
approval** mechanism that later slices (returns, discounts, voids) will depend on.

Still no backend. The work stays inside the same Flutter app and the same local SQLite
database, extended by a schema migration.

## Scope

### In scope

- **Staff ID + PIN login.** Every user gains a unique `staff_id` and an optional
  6-digit `pin_hash`. Cashiers log in with Staff ID + PIN. Username/password login is
  retained for managers/admins. Failed-PIN-attempt counting, lockout
  (`pin_locked_until`), manager unlock, PIN reset that forces a change on next login,
  and a PIN-change screen.
- **Quick lock / auto-lock.** A lock screen the signed-in user re-enters with their PIN;
  auto-locks after a configurable idle period.
- **Shift management.** A cashier starts a shift with an opening cash float and ends it
  by counting the drawer; the system computes expected cash (float + cash sales),
  variance, and a printable shift summary. No sale can be rung up without an open shift.
  Every sale is linked to its shift.
- **Cash drawer.** A drawer-event log: shift-open, shift-close, per-sale opening, and
  manager-approved no-sale openings. Pay-in / pay-out cash movements during a shift.
- **Manager approval.** A reusable approval prompt (manager Staff ID + PIN, or
  manager/admin username+password) gating: no-sale drawer opening, and closing a shift
  whose variance is non-zero.

### Explicitly deferred (later slices)

Returns & refunds; discounts & promotions; card / mobile-money / split / credit
payments; suppliers & purchasing; customers & loyalty; expiry/batch tracking; multi-
branch & multi-terminal; the Spring Boot backend, PostgreSQL, sync engine; Redis /
RabbitMQ; real hardware (thermal printer, scale, physical drawer kick); reports beyond
the daily and shift summaries; 2FA.

## Technology

Unchanged from Slice 1: Flutter Desktop, drift (SQLite), Riverpod, bcrypt, pdf +
printing, build_runner. No new packages expected.

## Architecture

The Slice 1 layering holds: UI → Riverpod providers → repositories → drift data source,
with pure-Dart domain logic. Slice 2 adds:

- `domain/` — `Shift`, `ShiftSummary`, `CashEvent` models; shift-calculation logic
  (expected cash, variance) as pure functions, unit-tested.
- `data/repositories/` — `shift_repository.dart`, extends `auth_repository.dart`.
- `features/auth/` — PIN login screen, PIN-change screen, lock screen.
- `features/shift/` — start-shift, end-shift, shift-summary screens.
- `shared/` — a `ManagerApproval` helper/dialog.

The repository seam still isolates SQLite so a future backend slots in unchanged.

## Data model (Slice 2 — schema version 2)

A drift migration upgrades `schemaVersion` 1 → 2.

### Changed table

- **users** — add `staff_id` (text, unique), `pin_hash` (text, nullable),
  `pin_failed_attempts` (int, default 0), `pin_locked_until` (datetime, nullable),
  `force_pin_change` (bool, default false), `last_login_at` (datetime, nullable).
  Existing rows get a generated `staff_id` during migration; the seeded admin keeps
  username/password login and gains a default PIN.

### Changed table

- **sales** — add `shift_id` (int, FK → shifts, nullable; required for sales created in
  Slice 2 onward — existing Slice 1 rows keep null).

### New tables

- **shifts** — `id, user_id (FK users), terminal_id (text), opening_float, status
  (open/closed), opened_at, closed_at (nullable), cash_sales_total, expected_cash
  (nullable), counted_cash (nullable), variance (nullable), closed_by (FK users,
  nullable), note, created_at`
- **cash_events** — `id, shift_id (FK shifts), user_id (FK users), type
  (shiftOpen/shiftClose/sale/noSale/payIn/payOut), amount (nullable), reason,
  approved_by (FK users, nullable), created_at`

All money stays integer minor units (cents).

## Behaviour decisions

- **Terminal id:** Slice 2 is still single-terminal — `terminal_id` is the constant
  `'TILL-001'`. Real terminal registration is a later slice.
- **Login routing:** the login screen offers two modes — *Staff PIN* (Staff ID +
  6-digit PIN) and *Manager* (username + password). A user without a `pin_hash` can only
  use Manager login; a user with one can use either.
- **PIN rules:** PIN is exactly 6 digits, bcrypt-hashed, never stored plain. 5 failed
  attempts locks the account for 15 minutes (or until a manager unlocks it). A successful
  login resets the counter and stamps `last_login_at`. After a manager PIN reset,
  `force_pin_change` is true and the user must set a new PIN before reaching the app.
- **Shift gating:** opening the Sell screen with no open shift for the current user
  shows a "Start your shift" prompt; sales are blocked until a shift is open. A user has
  at most one open shift at a time.
- **Expected cash:** `opening_float + cash_sales_total + payIn − payOut`. Variance =
  `counted_cash − expected_cash`. A non-zero variance requires manager approval to close.
- **Cash sales total:** maintained from completed cash sales linked to the shift (Slice 2
  has only cash payments, so every sale contributes).
- **Auto-lock:** after 5 minutes of no interaction the app shows the lock screen; the
  signed-in user unlocks with their PIN (managers without a PIN re-enter their password).
- **Seed:** the migration and `seedIfEmpty` ensure the admin has `staff_id` `ADM-001`
  and a default PIN `000000` with `force_pin_change = true`; a sample cashier
  (`CSH-001`, PIN `000000`, `force_pin_change = true`) is seeded so PIN login is testable
  immediately.

## Error handling

- PIN login: wrong PIN, unknown Staff ID, locked account, and inactive account each
  give a clear inline message; the locked-account message states when it unlocks.
- Starting a shift when one is already open, or selling with no open shift, is blocked
  with an explanatory message — never a crash.
- Ending a shift runs in a DB transaction (shift row + closing cash_event); on failure
  nothing is recorded and the shift stays open.
- Manager approval failure (bad credentials) cancels the guarded action; the action is
  never performed without a recorded approver.

## Testing

- **Pure-Dart unit tests** for shift calculations: expected cash, variance, with
  pay-in/pay-out, at minor-unit precision.
- **Repository tests** against in-memory SQLite: the v1→v2 migration (a v1 database
  upgrades cleanly and keeps its data); PIN verification incl. lockout after N failures
  and unlock; shift open/close with cash-event records; sale-to-shift linkage and
  `cash_sales_total` accumulation.
- **Widget tests:** PIN login (success, wrong PIN, locked account), forced PIN change,
  start-shift and end-shift flows, the manager-approval prompt.

## Out-of-scope reminders

No network calls, no backend, no sync. Still one terminal. Card/mobile payments,
returns, and discounts remain deferred — Slice 2 only adds identity, shift, and
drawer control on top of the Slice 1 cash till.
