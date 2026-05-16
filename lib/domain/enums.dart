// lib/domain/enums.dart

enum UserRole {
  cashier,
  manager,
  admin;

  /// Manager and admin may manage products; cashier may not.
  bool get canManageProducts => this == manager || this == admin;

  static UserRole? fromNameOrNull(String name) =>
      UserRole.values.where((r) => r.name == name).firstOrNull;

  static UserRole fromName(String name) =>
      fromNameOrNull(name) ??
      (throw ArgumentError.value(name, 'name', 'Unknown UserRole'));
}

enum SaleStatus {
  completed;

  static SaleStatus? fromNameOrNull(String name) =>
      SaleStatus.values.where((s) => s.name == name).firstOrNull;

  static SaleStatus fromName(String name) =>
      fromNameOrNull(name) ??
      (throw ArgumentError.value(name, 'name', 'Unknown SaleStatus'));
}

enum PaymentMethod {
  cash;

  static PaymentMethod? fromNameOrNull(String name) =>
      PaymentMethod.values.where((m) => m.name == name).firstOrNull;

  static PaymentMethod fromName(String name) =>
      fromNameOrNull(name) ??
      (throw ArgumentError.value(name, 'name', 'Unknown PaymentMethod'));
}

enum MovementType {
  sale,
  seed,
  adjustment;

  static MovementType? fromNameOrNull(String name) =>
      MovementType.values.where((t) => t.name == name).firstOrNull;

  static MovementType fromName(String name) =>
      fromNameOrNull(name) ??
      (throw ArgumentError.value(name, 'name', 'Unknown MovementType'));
}

enum ShiftStatus {
  open,
  closed;

  static ShiftStatus? fromNameOrNull(String name) =>
      ShiftStatus.values.where((s) => s.name == name).firstOrNull;

  static ShiftStatus fromName(String name) =>
      fromNameOrNull(name) ??
      (throw ArgumentError.value(name, 'name', 'Unknown ShiftStatus'));
}

enum CashEventType {
  shiftOpen,
  shiftClose,
  sale,
  noSale,
  payIn,
  payOut;

  static CashEventType? fromNameOrNull(String name) =>
      CashEventType.values.where((t) => t.name == name).firstOrNull;

  static CashEventType fromName(String name) =>
      fromNameOrNull(name) ??
      (throw ArgumentError.value(name, 'name', 'Unknown CashEventType'));
}
