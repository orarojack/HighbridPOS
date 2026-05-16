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
