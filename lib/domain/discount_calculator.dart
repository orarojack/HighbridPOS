// lib/domain/discount_calculator.dart

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
