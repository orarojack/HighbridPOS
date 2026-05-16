# HighbridPOS Slice 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Staff ID + PIN cashier login, cashier shift management, cash-drawer control, and a reusable manager-approval mechanism to the HighbridPOS desktop POS — completing the single-till MVP.

**Architecture:** Same layered Flutter app as Slice 1 (UI → Riverpod → repositories → drift SQLite, pure-Dart domain logic). Slice 2 extends the SQLite schema via a drift v1→v2 migration, adds shift/cash domain models + pure shift-calculation functions, two repositories' worth of new methods, and new auth/shift/lock UI. The repository seam is preserved.

**Tech Stack:** Flutter Desktop, drift (SQLite ORM), Riverpod, bcrypt, build_runner. No new packages.

---

## Prerequisite

Slice 1 is complete on branch `slice1-pos-terminal`; Slice 2 builds on it on branch
`slice2-pin-shifts`. Flutter SDK 3.41.9 is installed at `~/flutter` (on `PATH` via
`~/.bashrc`). Verification is `flutter analyze` + `flutter test` (the Linux desktop C++
toolchain is not installed, so `flutter run` is not used).

Design spec: `docs/superpowers/specs/2026-05-16-highbridpos-slice2-design.md`.

## Conventions carried from Slice 1

- Money is integer minor units (cents): `int`.
- drift row-class name collisions with domain classes are avoided with `@DataClassName`
  (Slice 1 did this for `Products`→`ProductData`, `Categories`→`CategoryData`).
- Domain model classes are immutable, with `==`/`hashCode`.
- Enums expose `.name`, `fromName` (throws `ArgumentError`), and `fromNameOrNull`.
- `flutter analyze` must stay clean; the SDK is newer than some package docs assume — a
  trivial deprecation rename or unused-import removal on the way is acceptable.
- TDD: write the failing test, see it fail, implement, see it pass, commit.

## File Structure

```
lib/data/db/app_database.dart        MODIFY — add columns + 2 tables, schemaVersion 2, onUpgrade
lib/data/db/seed.dart                MODIFY — staff_id + default PINs + sample cashier
lib/domain/enums.dart                MODIFY — add ShiftStatus, CashEventType
lib/domain/models.dart               MODIFY — add Shift, ShiftSummary, CashEvent
lib/domain/shift_calculator.dart     CREATE — pure expected-cash / variance functions
lib/data/repositories/auth_repository.dart   MODIFY — PIN login, lockout, unlock, PIN reset/change
lib/data/repositories/shift_repository.dart  CREATE — open/close shift, cash events, cash-sales
lib/data/repositories/sale_repository.dart   MODIFY — link completed sale to a shift
lib/providers.dart                   MODIFY — shiftRepositoryProvider
lib/features/auth/auth_controller.dart        MODIFY — track login, expose current user refresh
lib/features/auth/login_screen.dart  MODIFY — Staff PIN mode + Manager mode
lib/features/auth/pin_change_screen.dart      CREATE — forced / voluntary PIN change
lib/features/auth/lock_screen.dart   CREATE — quick-lock re-entry
lib/features/shift/shift_controller.dart      CREATE — current open shift state
lib/features/shift/start_shift_screen.dart    CREATE
lib/features/shift/end_shift_screen.dart      CREATE
lib/features/shift/shift_summary.dart         CREATE — on-screen summary widget
lib/features/pos/sale_screen.dart    MODIFY — gate on open shift; no-sale drawer button
lib/features/home_shell.dart         MODIFY — lock button, idle auto-lock, Shift nav
lib/shared/manager_approval.dart     CREATE — reusable approval dialog
test/shift_calculator_test.dart      CREATE
test/migration_test.dart             CREATE
test/pin_auth_test.dart              CREATE
test/shift_repository_test.dart      CREATE
test/pin_login_screen_test.dart      CREATE
test/shift_flow_test.dart            CREATE
```

---

### Task 1: Schema migration to version 2

Extend the drift schema with PIN columns on `users`, a `shift_id` on `sales`, and the
`Shifts` and `CashEvents` tables; bump `schemaVersion` to 2 with an `onUpgrade` that is
safe for an existing v1 database.

**Files:**
- Modify: `lib/data/db/app_database.dart`
- Generated: `lib/data/db/app_database.g.dart` (build_runner)
- Test: `test/migration_test.dart`

- [ ] **Step 1: Add the new columns and tables to the schema**

In `lib/data/db/app_database.dart`:

Add to the `Users` table (nullable at the SQLite level so the v1→v2 migration is safe;
the app always populates `staffId`):
```dart
  TextColumn get staffId => text().nullable().unique()();
  TextColumn get pinHash => text().nullable()();
  IntColumn get pinFailedAttempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get pinLockedUntil => dateTime().nullable()();
  BoolColumn get forcePinChange => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastLoginAt => dateTime().nullable()();
```

Add to the `Sales` table:
```dart
  IntColumn get shiftId => integer().nullable().references(Shifts, #id)();
```

Add two new tables (place above `@DriftDatabase`):
```dart
@DataClassName('ShiftRow')
class Shifts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().references(Users, #id)();
  TextColumn get terminalId => text()();
  IntColumn get openingFloat => integer()();
  TextColumn get status => text()(); // ShiftStatus.name
  DateTimeColumn get openedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get closedAt => dateTime().nullable()();
  IntColumn get cashSalesTotal => integer().withDefault(const Constant(0))();
  IntColumn get payInTotal => integer().withDefault(const Constant(0))();
  IntColumn get payOutTotal => integer().withDefault(const Constant(0))();
  IntColumn get expectedCash => integer().nullable()();
  IntColumn get countedCash => integer().nullable()();
  IntColumn get variance => integer().nullable()();
  IntColumn get closedBy => integer().nullable().references(Users, #id)();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('CashEventRow')
class CashEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get shiftId => integer().references(Shifts, #id)();
  IntColumn get userId => integer().references(Users, #id)();
  TextColumn get type => text()(); // CashEventType.name
  IntColumn get amount => integer().nullable()();
  TextColumn get reason => text().withDefault(const Constant(''))();
  IntColumn get approvedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
```

Add `Shifts` and `CashEvents` to the `@DriftDatabase(tables: [...])` list.

- [ ] **Step 2: Bump schemaVersion and add onUpgrade**

Change `schemaVersion` to `2`. Update the `MigrationStrategy` (keep the existing
`onCreate` and the `beforeOpen` `PRAGMA foreign_keys = ON`) to add `onUpgrade`:
```dart
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(users, users.staffId);
            await m.addColumn(users, users.pinHash);
            await m.addColumn(users, users.pinFailedAttempts);
            await m.addColumn(users, users.pinLockedUntil);
            await m.addColumn(users, users.forcePinChange);
            await m.addColumn(users, users.lastLoginAt);
            await m.createTable(shifts);
            await m.createTable(cashEvents);
            await m.addColumn(sales, sales.shiftId);
            // Backfill staff_id for any pre-existing users.
            final existing = await select(users).get();
            for (final u in existing) {
              await (update(users)..where((t) => t.id.equals(u.id)))
                  .write(UsersCompanion(
                staffId: Value('USR-${u.id.toString().padLeft(3, '0')}'),
              ));
            }
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
```

- [ ] **Step 3: Regenerate drift code**

Run: `dart run build_runner build` (generous timeout; `--delete-conflicting-outputs` is
ignored by the installed build_runner — the plain command works).
Expected: `app_database.g.dart` regenerates with `ShiftRow`, `CashEventRow`, and the new
`Users`/`Sales` columns.

- [ ] **Step 4: Write the migration test**

`test/migration_test.dart` — open a v1-shaped database, then verify a v2 `AppDatabase`
upgrades it without data loss. drift exposes schema-aware helpers, but the simplest
robust approach: build a v1 schema by raw SQL in an in-memory `NativeDatabase`, insert a
user row, then construct `AppDatabase` over the same connection and confirm the upgrade
ran. If a full v1-replica is impractical, instead test the *forward* path: a fresh v2
`AppDatabase` (`onCreate`) has all new tables/columns and `seedIfEmpty` works. At minimum
the test MUST assert: a fresh v2 DB has `shifts` and `cash_events` tables and the new
`users` columns, and `schemaVersion == 2`. Write the test, then:

- [ ] **Step 5: Run tests**

Run: `flutter test test/migration_test.dart` — expect PASS.
Run: `flutter analyze` — expect `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/data/db/app_database.dart lib/data/db/app_database.g.dart test/migration_test.dart
git commit -m "feat: migrate schema to v2 — PIN columns, shifts, cash events"
```

---

### Task 2: Domain enums, models, and shift calculation

Add the Slice 2 enums and immutable models, plus pure shift-calculation functions.

**Files:**
- Modify: `lib/domain/enums.dart`, `lib/domain/models.dart`
- Create: `lib/domain/shift_calculator.dart`
- Test: `test/shift_calculator_test.dart`

- [ ] **Step 1: Add enums**

In `lib/domain/enums.dart`, add (follow the existing enum style — each with `fromName`
throwing `ArgumentError` and `fromNameOrNull`):
```dart
enum ShiftStatus { open, closed; /* fromName / fromNameOrNull */ }
enum CashEventType {
  shiftOpen, shiftClose, sale, noSale, payIn, payOut;
  /* fromName / fromNameOrNull */
}
```

- [ ] **Step 2: Add models**

In `lib/domain/models.dart`, add immutable classes with `==`/`hashCode` (match the
existing model style):
- `Shift` — `id, userId, terminalId, openingFloat, status (ShiftStatus), openedAt,
  closedAt (nullable), cashSalesTotal, payInTotal, payOutTotal, expectedCash (nullable),
  countedCash (nullable), variance (nullable), closedBy (nullable), note`
- `CashEvent` — `id, shiftId, userId, type (CashEventType), amount (nullable), reason,
  approvedBy (nullable), createdAt`
- `ShiftSummary` — `shift (Shift), cashierName (String), eventCount (int)`

- [ ] **Step 3: Write the failing shift-calculator test**

`test/shift_calculator_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/domain/shift_calculator.dart';

void main() {
  test('expectedCash sums float, cash sales, pay-ins minus pay-outs', () {
    expect(
      expectedCash(openingFloat: 5000, cashSales: 42000, payIn: 0, payOut: 0),
      47000,
    );
    expect(
      expectedCash(openingFloat: 5000, cashSales: 42000, payIn: 1000, payOut: 500),
      47500,
    );
  });

  test('variance is counted minus expected', () {
    expect(cashVariance(counted: 46500, expected: 47000), -500);
    expect(cashVariance(counted: 47000, expected: 47000), 0);
    expect(cashVariance(counted: 47200, expected: 47000), 200);
  });
}
```

- [ ] **Step 4: Run it, watch it fail**

Run: `flutter test test/shift_calculator_test.dart` — expect FAIL (file missing).

- [ ] **Step 5: Implement `lib/domain/shift_calculator.dart`**

Pure Dart, no imports:
```dart
/// Cash the drawer should hold = float + cash sales + pay-ins − pay-outs. All cents.
int expectedCash({
  required int openingFloat,
  required int cashSales,
  required int payIn,
  required int payOut,
}) =>
    openingFloat + cashSales + payIn - payOut;

/// Variance = counted − expected. Negative means a shortage. All cents.
int cashVariance({required int counted, required int expected}) =>
    counted - expected;
```

- [ ] **Step 6: Run tests + analyze**

Run: `flutter test test/shift_calculator_test.dart` — expect PASS.
Run: `flutter analyze` — expect `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add lib/domain/ test/shift_calculator_test.dart
git commit -m "feat: add shift/cash domain models and shift calculation"
```

---

### Task 3: Seeding update

Give every seeded user a `staff_id` and a default PIN, and add a sample cashier so PIN
login is testable immediately.

**Files:**
- Modify: `lib/data/db/seed.dart`

- [ ] **Step 1: Update `seedIfEmpty`**

In the seed transaction, set the admin user's `staffId: 'ADM-001'`,
`pinHash: BCrypt.hashpw('000000', BCrypt.gensalt())`, `forcePinChange: true`. Then add a
second seeded user: a cashier — `username 'cashier'`, `fullName 'Sample Cashier'`,
`role UserRole.cashier.name`, `staffId 'CSH-001'`, `passwordHash` of `'cashier123'`,
`pinHash` of `'000000'`, `forcePinChange: true`, `active: true`.

Keep the existing categories/products/stock-movements seeding unchanged. The first-run
guard (`if (existing.isNotEmpty) return`) stays.

- [ ] **Step 2: Verify**

Run: `flutter analyze` — expect `No issues found!`.
Run: `flutter test` — full suite still passes (the Slice 1 repository tests seed a fresh
DB; confirm none break — if a Slice 1 test asserted an exact user count, update it to
reflect 2 seeded users and note it in the task report).

- [ ] **Step 3: Commit**

```bash
git add lib/data/db/seed.dart
git commit -m "feat: seed staff IDs, default PINs, and a sample cashier"
```

---

### Task 4: PIN authentication in the auth repository

Add PIN login with failed-attempt counting, lockout, manager unlock, and PIN
reset/change to `AuthRepository`.

**Files:**
- Modify: `lib/data/repositories/auth_repository.dart`
- Test: `test/pin_auth_test.dart`

- [ ] **Step 1: Write the failing tests**

`test/pin_auth_test.dart` — against an in-memory `AppDatabase` seeded via `seedIfEmpty`.
Tests (use the seeded cashier `CSH-001`, PIN `000000`):
- `loginWithPin` with correct Staff ID + PIN returns the `AppUser`; `last_login_at` is
  set; `pin_failed_attempts` reset to 0.
- `loginWithPin` with a wrong PIN returns `null` and increments `pin_failed_attempts`.
- After 5 consecutive wrong PINs the account is locked: `pin_locked_until` is in the
  future, and even a correct PIN returns `null` (a distinct locked result — see Step 2).
- `unlockPin(staffId)` clears `pin_locked_until` and resets `pin_failed_attempts`.
- `resetPin(userId, newPin)` sets a new `pin_hash` and `force_pin_change = true`.
- `changePin(userId, newPin)` sets a new `pin_hash` and `force_pin_change = false`.

- [ ] **Step 2: Run tests, watch them fail**

Run: `flutter test test/pin_auth_test.dart` — expect FAIL (methods undefined).

- [ ] **Step 3: Implement the methods**

Add to `AuthRepository`. Define a small result type so the UI can distinguish
locked-out from wrong-PIN:
```dart
enum PinLoginOutcome { ok, badCredentials, locked, inactive }

class PinLoginResult {
  final PinLoginOutcome outcome;
  final AppUser? user;
  final DateTime? lockedUntil;
  const PinLoginResult(this.outcome, {this.user, this.lockedUntil});
}
```
Methods:
- `Future<PinLoginResult> loginWithPin(String staffId, String pin)` — look up the user
  by `staffId`; if missing → `badCredentials`; if `!active` → `inactive`; if
  `pinLockedUntil` is set and in the future → `locked`; verify `pin` against `pinHash`
  with `BCrypt.checkpw`. On success: reset `pinFailedAttempts` to 0, clear
  `pinLockedUntil`, set `lastLoginAt = DateTime.now()`, return `ok` with the user. On
  failure: increment `pinFailedAttempts`; if it reaches 5, set
  `pinLockedUntil = DateTime.now().add(const Duration(minutes: 15))`; return
  `badCredentials` (or `locked` if it just locked).
- `Future<void> unlockPin(String staffId)` — clear `pinLockedUntil`, reset
  `pinFailedAttempts` to 0.
- `Future<void> resetPin(int userId, String newPin)` — `pinHash = BCrypt.hashpw(...)`,
  `forcePinChange = true`, clear lock + attempts.
- `Future<void> changePin(int userId, String newPin)` — `pinHash = BCrypt.hashpw(...)`,
  `forcePinChange = false`.
- Keep the existing `login(username, password)`; on its success also set `lastLoginAt`.

The PIN must be exactly 6 digits — validate in the UI (Task 7), but `loginWithPin` should
treat a malformed PIN as `badCredentials` rather than throwing.

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/pin_auth_test.dart` — expect PASS.
Run: `flutter analyze` — expect `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/auth_repository.dart test/pin_auth_test.dart
git commit -m "feat: add PIN login with lockout, unlock, and PIN reset/change"
```

---

### Task 5: Shift repository

Open/close shifts, record cash events, accumulate cash sales, and link sales to shifts.

**Files:**
- Create: `lib/data/repositories/shift_repository.dart`
- Test: `test/shift_repository_test.dart`

- [ ] **Step 1: Write the failing tests**

`test/shift_repository_test.dart` — in-memory `AppDatabase` + `seedIfEmpty`. Tests:
- `openShift(userId, terminalId, openingFloat)` creates an `open` shift and writes a
  `shiftOpen` cash event with `amount == openingFloat`.
- `currentOpenShift(userId)` returns the open shift, or `null` when none / after close.
- `openShift` throws `ShiftAlreadyOpenException` if the user already has an open shift.
- `recordCashSale(shiftId, amount)` increases the shift's `cashSalesTotal` and writes a
  `sale` cash event.
- `addCashMovement(shiftId, userId, payIn/payOut, amount, reason)` updates
  `payInTotal`/`payOutTotal` and writes the matching cash event.
- `recordNoSale(shiftId, userId, approvedBy, reason)` writes a `noSale` cash event with
  `approvedBy` set.
- `closeShift(shiftId, countedCash, closedBy, note)` sets `status = closed`, computes
  and stores `expectedCash`/`variance` (via `shift_calculator`), stamps `closedAt`,
  writes a `shiftClose` cash event — all in one transaction.
- `shiftSummary(shiftId)` returns a `ShiftSummary` with the closed shift, cashier name,
  and cash-event count.

- [ ] **Step 2: Run, watch fail**

Run: `flutter test test/shift_repository_test.dart` — expect FAIL.

- [ ] **Step 3: Implement `lib/data/repositories/shift_repository.dart`**

`ShiftRepository(AppDatabase db)`. Public methods return domain models (`Shift`,
`CashEvent`, `ShiftSummary`) via private `_toShift` / `_toCashEvent` mappers — never
drift rows. Define `class ShiftAlreadyOpenException implements Exception`. `closeShift`
wraps its writes in `db.transaction`. `expectedCash`/`variance` come from
`lib/domain/shift_calculator.dart`. `recordCashSale` and `addCashMovement` each update
the shift row and insert the cash event (a transaction each).

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/shift_repository_test.dart` — expect PASS.
Run: `flutter analyze` — expect `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/shift_repository.dart test/shift_repository_test.dart
git commit -m "feat: add shift repository — open/close, cash events, summaries"
```

---

### Task 6: Sale-to-shift linkage

A completed cash sale records its `shift_id` and feeds the shift's cash total.

**Files:**
- Modify: `lib/data/repositories/sale_repository.dart`
- Test: `test/shift_repository_test.dart` (extend)

- [ ] **Step 1: Write the failing test**

Extend `test/shift_repository_test.dart` (or add to a sale-focused test): open a shift,
complete a cash sale via `SaleRepository.completeCashSale(... shiftId: shift.id ...)`,
then assert the persisted `sales` row has `shiftId == shift.id` and the shift's
`cashSalesTotal` equals the sale total.

- [ ] **Step 2: Run, watch fail**

Run: `flutter test test/shift_repository_test.dart` — expect FAIL (param missing).

- [ ] **Step 3: Implement**

Add a required `int shiftId` parameter to `SaleRepository.completeCashSale`. Inside the
existing sale transaction: write `shiftId` onto the `sales` row, and after the sale is
recorded, increment the shift's `cashSalesTotal` by the sale total and insert a `sale`
cash event (reuse `ShiftRepository.recordCashSale` logic, or inline the same writes
within the one transaction — keep it atomic with the sale).

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test` — full suite passes. Note: Slice 1 `repositories_test.dart` calls
`completeCashSale` without `shiftId`; update those call sites to open a shift in the test
setup and pass `shift.id`. Report which tests were updated.
Run: `flutter analyze` — expect `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/sale_repository.dart test/
git commit -m "feat: link completed sales to the active shift"
```

---

### Task 7: Providers and manager-approval helper

Wire the shift repository into Riverpod and build the reusable manager-approval dialog.

**Files:**
- Modify: `lib/providers.dart`
- Create: `lib/shared/manager_approval.dart`

- [ ] **Step 1: Add the provider**

In `lib/providers.dart` add `shiftRepositoryProvider` (a `Provider<ShiftRepository>`
watching `databaseProvider`), mirroring the existing repository providers.

- [ ] **Step 2: Build the manager-approval helper**

`lib/shared/manager_approval.dart` — `Future<AppUser?> requestManagerApproval(
BuildContext context, WidgetRef ref, {required String action})`. It shows a dialog
asking for a manager/admin credential: a Staff ID + PIN field set, validated via
`AuthRepository.loginWithPin`, OR a username + password set validated via
`AuthRepository.login`. The dialog accepts only a user whose role is `manager` or
`admin` (`UserRole.canManageProducts`); a cashier credential is rejected with an inline
message. Returns the approving `AppUser` on success, `null` if cancelled. The `action`
string is shown in the dialog title (e.g. "Approve: open drawer (no sale)").

- [ ] **Step 3: Verify**

Run: `flutter analyze` — expect `No issues found!`.

- [ ] **Step 4: Commit**

```bash
git add lib/providers.dart lib/shared/manager_approval.dart
git commit -m "feat: add shift provider and reusable manager-approval dialog"
```

---

### Task 8: PIN login screen and forced PIN change

Rework the login screen to offer Staff PIN and Manager modes; add the PIN-change screen.

**Files:**
- Modify: `lib/features/auth/login_screen.dart`, `lib/features/auth/auth_controller.dart`
- Create: `lib/features/auth/pin_change_screen.dart`
- Test: `test/pin_login_screen_test.dart`

- [ ] **Step 1: Extend the auth controller**

In `auth_controller.dart` add `loginWithPin(String staffId, String pin)` returning a
result the UI can branch on (success / wrong-PIN / locked / inactive — reuse
`PinLoginResult` from Task 4). On success set the state user. Keep the existing
`login`/`logout`. Add a way for the UI to know `forcePinChange` for the logged-in user
(the `AppUser` model — add a `forcePinChange` bool field to `AppUser`, populated by both
login paths and the `_toUser` mapper; default false).

- [ ] **Step 2: Rework the login screen**

`login_screen.dart` — a segmented control / tabs with two modes:
- **Staff PIN:** a Staff ID text field + a 6-digit PIN field (obscured, numeric). On
  submit call `loginWithPin`. Show inline errors: wrong PIN, unknown Staff ID, "Account
  locked until HH:MM", inactive.
- **Manager:** the existing username + password fields and flow.
After a successful login, if the user's `forcePinChange` is true, route to
`PinChangeScreen` (forced mode) instead of the home shell.

- [ ] **Step 3: Build the PIN-change screen**

`pin_change_screen.dart` — two 6-digit fields (new PIN, confirm). Validates: exactly 6
digits, both match. Calls `AuthRepository.changePin`. In forced mode it cannot be
dismissed without completing; in voluntary mode (opened from the home shell later) it
has a cancel. On success continues to the home shell.

- [ ] **Step 4: Write widget tests**

`test/pin_login_screen_test.dart` — in-memory DB + seed. Tests: PIN login success with
`CSH-001`/`000000` routes onward; wrong PIN shows the error; 5 wrong PINs then a correct
one shows the locked message; a forced-PIN-change user lands on `PinChangeScreen`.
(Match the desktop-viewport test pattern from Slice 1's `sale_screen_test.dart` if any
screen is wide.)

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/pin_login_screen_test.dart` — expect PASS.
Run: `flutter test` — full suite passes.
Run: `flutter analyze` — expect `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/auth/ test/pin_login_screen_test.dart
git commit -m "feat: add Staff ID + PIN login and forced PIN change"
```

---

### Task 9: Lock screen and auto-lock

Add a quick-lock screen and idle auto-lock.

**Files:**
- Create: `lib/features/auth/lock_screen.dart`
- Modify: `lib/features/home_shell.dart`, `lib/app.dart`

- [ ] **Step 1: Build the lock screen**

`lock_screen.dart` — shows the signed-in user's name and a re-entry field: a 6-digit PIN
field for users with a `pinHash`, a password field for managers without one. On correct
re-entry it dismisses; it cannot be bypassed. Wrong entry shows an inline error. It does
NOT log the user out — identity is retained.

- [ ] **Step 2: Wire locking into the shell**

In `home_shell.dart`: add a "Lock" button in the rail/app bar that shows the lock
screen. Wrap the shell body in a `Listener`/`GestureDetector` (or use a
`RestartableTimer`) that resets a 5-minute idle timer on interaction; when it fires,
show the lock screen. The lock state is local UI state (a `bool` in the shell or a small
provider) — when locked, the lock screen overlays the shell.

- [ ] **Step 3: Verify**

Run: `flutter test` — full suite passes (no regressions).
Run: `flutter analyze` — expect `No issues found!`.

- [ ] **Step 4: Commit**

```bash
git add lib/features/auth/lock_screen.dart lib/features/home_shell.dart lib/app.dart
git commit -m "feat: add quick-lock screen and idle auto-lock"
```

---

### Task 10: Shift screens and Sell-screen gating

Add start-shift, end-shift, and shift-summary screens; block selling without an open
shift; add the no-sale drawer action.

**Files:**
- Create: `lib/features/shift/shift_controller.dart`, `start_shift_screen.dart`,
  `end_shift_screen.dart`, `shift_summary.dart`
- Modify: `lib/features/pos/sale_screen.dart`, `lib/features/home_shell.dart`
- Test: `test/shift_flow_test.dart`

- [ ] **Step 1: Shift controller**

`shift_controller.dart` — a Riverpod controller exposing the current open shift for the
signed-in user (`AsyncValue<Shift?>` or a `StateNotifier`). Methods: `start(openingFloat)`,
`end(countedCash, note, closedBy)`, refresh. Backed by `shiftRepositoryProvider`.

- [ ] **Step 2: Start-shift screen**

`start_shift_screen.dart` — an opening-float money field (parsed with `parseMoney`),
a "Start shift" button calling `shiftController.start`. On success routes to the Sell
screen. Shows an error if a shift is already open.

- [ ] **Step 3: End-shift screen**

`end_shift_screen.dart` — shows the open shift's opening float and accumulated cash
sales / expected cash; a counted-cash money field; computes and displays the variance
live. "Close shift" calls `shiftController.end`. If the variance is non-zero, first
require `requestManagerApproval` (Task 7) — pass the approver as `closedBy`; if approval
is cancelled, the shift stays open. On success shows the `ShiftSummary`.

- [ ] **Step 4: Shift summary widget**

`shift_summary.dart` — an on-screen summary (opening float, cash sales, pay-in/out,
expected, counted, variance, cashier, times). A "Print / PDF" action reusing the
Slice 1 `printing` approach is optional but preferred; if included, keep the PDF builder
small and pure like `receipt.dart`.

- [ ] **Step 5: Gate the Sell screen**

In `sale_screen.dart`: on entry, if there is no open shift for the signed-in user, show
a "Start your shift to begin selling" panel with a button to the start-shift screen
instead of the sale UI; block `completeCashSale` until a shift is open, and pass the
open shift's id into `completeCashSale` (Task 6). Add a "No-sale (open drawer)" button
that calls `requestManagerApproval` then `ShiftRepository.recordNoSale`.

- [ ] **Step 6: Home-shell navigation**

In `home_shell.dart` add a "Shift" rail destination showing start-shift or end-shift
depending on whether a shift is open.

- [ ] **Step 7: Widget tests**

`test/shift_flow_test.dart` — desktop-viewport widget tests: starting a shift from the
Sell screen's gate, the Sell screen becoming usable once a shift is open, ending a shift
with a zero variance (no approval needed) showing the summary, and ending with a
non-zero variance requiring the manager-approval dialog.

- [ ] **Step 8: Run tests + analyze**

Run: `flutter test` — full suite passes.
Run: `flutter analyze` — expect `No issues found!`.

- [ ] **Step 9: Commit**

```bash
git add lib/features/shift/ lib/features/pos/sale_screen.dart lib/features/home_shell.dart test/shift_flow_test.dart
git commit -m "feat: add shift start/end/summary screens and Sell-screen gating"
```

---

### Task 11: Final verification

**Files:** none — verification only.

- [ ] **Step 1: Full analyze + test**

Run: `flutter analyze` — expect `No issues found!`.
Run: `flutter test` — expect all tests pass; record the count.

- [ ] **Step 2: Spec coverage self-check**

Confirm against `docs/superpowers/specs/2026-05-16-highbridpos-slice2-design.md` that
every in-scope item is implemented: PIN login + lockout + unlock + reset + forced change;
quick-lock + auto-lock; shift start/end/summary; sell-screen gating; cash events incl.
no-sale; manager approval on no-sale and variance close; the v2 migration.

- [ ] **Step 3: Final commit**

```bash
git commit --allow-empty -m "chore: HighbridPOS Slice 2 complete"
```

---

## Self-Review Notes

**Spec coverage** — PIN login/lockout/unlock/reset/forced-change (Tasks 4, 8); quick-lock
+ auto-lock (Task 9); shift management (Tasks 5, 10); cash drawer + events (Tasks 5, 10);
manager approval (Tasks 7, 10); v1→v2 migration (Task 1); shift calculations (Task 2);
seeding (Task 3); sale-to-shift linkage (Task 6).

**Type consistency** — `ShiftStatus`/`CashEventType` (Task 2) used by the schema string
columns (Task 1) and repository (Task 5). `Shift`/`CashEvent`/`ShiftSummary` defined in
Task 2, returned by the repository in Task 5. `PinLoginResult`/`PinLoginOutcome` defined
in Task 4, reused by the controller and UI in Task 8. `completeCashSale` gains `shiftId`
in Task 6 — all call sites (Slice 1 tests, Task 10 sale screen) updated accordingly.

**Migration risk** — `staff_id` is nullable at the SQLite level specifically so the
v1→v2 `addColumn` is safe on a populated table; the app always sets it. The migration
test (Task 1) is the guard.
