# HighbridPOS — Slice 1 Design

**Date:** 2026-05-15
**Status:** Approved

## Context

The broader goal is a large supermarket POS and inventory system (Flutter desktop POS,
Spring Boot backend, PostgreSQL, React/Next.js admin dashboard, offline sync). That full
system is a multi-month, multi-application effort and cannot be built in one pass. It will
be built incrementally, one well-scoped, working, tested slice at a time.

**Slice 1** is a standalone Flutter desktop POS terminal that runs with **no backend**.
It is the foundation a real till could operate on. The local-SQLite design is part of the
plan's final architecture (offline SQLite per terminal), so this slice is not throwaway work.

## Scope

### In scope

- **Auth:** local user accounts with roles (cashier / manager / admin), password login/logout.
- **Product management:** add / edit / deactivate products; categories; prices; barcode; SKU.
- **Core sale loop:** product search & barcode lookup → add/remove cart items → change
  quantity → subtotal + per-line tax + total → cash payment with change due → recorded sale
  → automatic stock deduction.
- **Receipts:** on-screen receipt + PDF export after each sale.
- **Daily sales summary:** basic per-day totals screen.

### Explicitly deferred (later slices)

Card / mobile-money / split / credit payments; discounts & promotions; returns & refunds;
customers & loyalty; suppliers & purchasing; multi-branch & multi-terminal; offline sync
engine; Spring Boot backend & PostgreSQL; real thermal-printer / barcode-scanner / scale
hardware integration; Redis / RabbitMQ; reports beyond the daily summary.

## Technology

- **Flutter Desktop** — targets Linux first; Windows/macOS compatible.
- **drift** — type-safe SQLite ORM with compile-checked queries and built-in migrations.
- **Riverpod** — state management; testable, no global mutable state.
- **bcrypt** — password hashing.
- **pdf** + **printing** — receipt rendering and PDF export.

## Architecture

Layered, with the **repository layer** as the strict seam. When the Spring Boot backend is
built later, an HTTP data source replaces the SQLite data source behind the repository
interfaces without changing UI or domain logic.

```
UI (screens / widgets)
   |  Riverpod providers (state)
Domain (models + sale-calculation logic — pure Dart, no DB)
   |
Repositories (interfaces)
   |
Data source: SQLite        <- later: HTTP backend slots in here
```

### Project structure

```
lib/
  main.dart, app.dart
  data/db/             drift database, table definitions, DAOs
  data/repositories/   repository interfaces + SQLite implementations
  domain/              models + sale-calculation logic
  features/auth/       login screen + auth state
  features/pos/        sale screen, cart, payment dialog, receipt
  features/products/   product list + add/edit form
  features/reports/    daily summary screen
  shared/              theme, common widgets, routing
test/
```

## Data model (slice 1 tables)

A subset of the plan's 31 tables, named so the rest extend cleanly later.

- **users** — `id, username (unique), password_hash, full_name, role, active, created_at`
- **categories** — `id, name (unique)`
- **products** — `id, sku (unique), barcode (unique, nullable), name, description,
  category_id (FK), cost_price, sell_price, tax_rate, stock_qty, reorder_level, active,
  created_at, updated_at`
- **sales** — `id, reference_no (unique), cashier_id (FK users), subtotal, tax_total,
  total, status, created_at`
- **sale_items** — `id, sale_id (FK), product_id (FK), name_snapshot, unit_price,
  tax_rate, qty, line_tax, line_total`
- **payments** — `id, sale_id (FK), method, amount, tendered, change_due, created_at`
- **stock_movements** — `id, product_id (FK), type, qty_delta, ref_type, ref_id, note,
  created_at`

A completed sale writes `sales` + `sale_items` + `payments` + `stock_movements` rows in a
**single transaction**, so stock and money never disagree.

## Behaviour decisions

- **Sale reference:** `YYYYMMDD-NNNN`, sequential per calendar day.
- **Tax:** per-product `tax_rate`; tax computed per line; receipt shows the tax total.
  Prices are stored tax-exclusive; line total = `unit_price * qty`, line tax =
  `round(line_total * tax_rate)`.
- **Money:** all monetary amounts stored as integer minor units (cents) to avoid floating
  point error.
- **Stock guard:** the cart cannot hold more units of a product than its current
  `stock_qty`; the UI shows a clear message instead of allowing it.
- **Sale items snapshot** product name, unit price, and tax rate at sale time, so later
  product edits do not rewrite history.
- **First run:** seeds one `admin` user (username `admin`, default password `admin123`)
  and a small sample product catalog with categories, so the app is usable immediately.
- **Roles:** `cashier` can ring up sales; `manager` and `admin` can additionally manage
  products. The product-management UI is hidden/blocked for `cashier`.
- **Sale reference / cart state** is held in memory until the sale is completed; an
  abandoned cart simply clears.

## Error handling

- Login: invalid credentials and inactive accounts produce a clear inline error; no
  account lockout in slice 1.
- Sale completion runs in a DB transaction; on failure the cart is preserved and an error
  is surfaced — no partial sale is recorded.
- Cash payment requires `tendered >= total`; change due is computed and shown.
- Product save validates required fields and unique `sku` / `barcode`.

## Testing

- **Pure-Dart unit tests** for sale-calculation logic: per-line tax, subtotal, tax total,
  grand total, change due, rounding at minor-unit precision.
- **Repository tests** against an in-memory SQLite database: product CRUD, sale completion
  transaction, stock deduction and `stock_movements` records, daily summary aggregation,
  sale-reference sequencing.
- **Widget tests:** login flow (success, bad password, inactive user) and the POS sale
  screen (add item, stock guard, complete cash sale).

## Out-of-scope reminders

No network calls, no sync, no external services. The app is fully functional offline by
construction because there is no backend yet.
