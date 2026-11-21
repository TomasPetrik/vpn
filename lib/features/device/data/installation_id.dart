import 'package:uuid/uuid.dart';

/// Deterministic installation UUID from a stable hardware/vendor device id.
///
/// Survives secure-storage wipes (reinstall, package rename, clear data) as
/// long as [deviceIdentifier] stays the same — same approach as using
/// `MobileDeviceIdentifier` in mobile-flutter-merchant / wow_swift.
String? stableInstallationId({
  required String platform,
  required String? deviceIdentifier,
}) {
  final stable = deviceIdentifier?.trim();
  if (stable == null || stable.isEmpty) {
    return null;
  }
  return const Uuid().v5(
    Uuid.NAMESPACE_URL,
    'petrikvpn:$platform:$stable',
  );
}
