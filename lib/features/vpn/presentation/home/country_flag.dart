String countryFlagEmoji(String? countryCode) {
  if (countryCode == null || countryCode.length != 2) {
    return '🌐';
  }
  final code = countryCode.toUpperCase();
  final a = code.codeUnitAt(0);
  final b = code.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) {
    return '🌐';
  }
  return String.fromCharCodes([0x1F1E6 + (a - 65), 0x1F1E6 + (b - 65)]);
}
