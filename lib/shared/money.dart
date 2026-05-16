// lib/shared/money.dart

/// Formats integer minor units (cents) as a plain 2-decimal string.
/// Negative values produce a leading minus sign (e.g. -199 → '-1.99').
String formatMoney(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final frac = (abs % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$whole.$frac';
}

/// Parses a non-negative decimal string into integer minor units (cents).
/// Returns null if the input is not a valid non-negative number.
/// Input is expected to have at most 2 decimal places; additional decimal
/// digits are rounded via (value * 100).round() and may be slightly imprecise
/// due to IEEE-754 floating-point representation.
int? parseMoney(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final value = double.tryParse(trimmed);
  if (value == null || value < 0 || value.isNaN || value.isInfinite) {
    return null;
  }
  return (value * 100).round();
}
