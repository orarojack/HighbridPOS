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
  TextColumn get staffId => text().nullable().unique()();
  TextColumn get pinHash => text().nullable()();
  IntColumn get pinFailedAttempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get pinLockedUntil => dateTime().nullable()();
  BoolColumn get forcePinChange => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastLoginAt => dateTime().nullable()();
}

@DataClassName('CategoryData')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
}

@DataClassName('ProductData')
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
  IntColumn get shiftId => integer().nullable().references(Shifts, #id)();
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
  // Polymorphic reference: refType names the source entity kind (e.g. 'sale'),
  // refId its id. No FK constraint because the target table varies.
  TextColumn get refType => text().nullable()();
  IntColumn get refId => integer().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

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

@DriftDatabase(tables: [
  Users,
  Categories,
  Products,
  Sales,
  SaleItems,
  Payments,
  StockMovements,
  Shifts,
  CashEvents,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // SQLite cannot ALTER TABLE ADD COLUMN a UNIQUE column, so
            // staff_id is added plain and its uniqueness is enforced by a
            // separate unique index (matching the @unique() in the schema).
            await customStatement(
              'ALTER TABLE "users" ADD COLUMN "staff_id" TEXT NULL',
            );
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS '
              'users_staff_id_unique ON "users" ("staff_id")',
            );
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
}
