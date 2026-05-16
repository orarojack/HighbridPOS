// lib/domain/enums.dart

enum UserRole {
  cashier,
  manager,
  admin;

  /// Manager and admin may manage products; cashier may not.
  bool get canManageProducts => this == manager || this == admin;

  static UserRole fromName(String name) =>
      UserRole.values.firstWhere((r) => r.name == name);
}

enum SaleStatus {
  completed;

  static SaleStatus fromName(String name) =>
      SaleStatus.values.firstWhere((s) => s.name == name);
}

enum PaymentMethod {
  cash;

  static PaymentMethod fromName(String name) =>
      PaymentMethod.values.firstWhere((m) => m.name == name);
}

enum MovementType {
  sale,
  seed,
  adjustment;

  static MovementType fromName(String name) =>
      MovementType.values.firstWhere((t) => t.name == name);
}
