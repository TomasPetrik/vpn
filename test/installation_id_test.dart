import 'package:flutter_test/flutter_test.dart';
import 'package:ru_eu_vpn/features/device/data/installation_id.dart';

void main() {
  test('stableInstallationId is deterministic for same device', () {
    final a = stableInstallationId(
      platform: 'android',
      deviceIdentifier: 'AA:BB:CC',
    );
    final b = stableInstallationId(
      platform: 'android',
      deviceIdentifier: 'AA:BB:CC',
    );
    expect(a, isNotNull);
    expect(a, b);
  });

  test('stableInstallationId differs by platform and identifier', () {
    final android = stableInstallationId(
      platform: 'android',
      deviceIdentifier: 'AA:BB:CC',
    );
    final ios = stableInstallationId(
      platform: 'ios',
      deviceIdentifier: 'AA:BB:CC',
    );
    final other = stableInstallationId(
      platform: 'android',
      deviceIdentifier: 'DD:EE:FF',
    );
    expect(android, isNot(ios));
    expect(android, isNot(other));
  });

  test('stableInstallationId returns null without device identifier', () {
    expect(
      stableInstallationId(platform: 'android', deviceIdentifier: null),
      isNull,
    );
    expect(
      stableInstallationId(platform: 'android', deviceIdentifier: '  '),
      isNull,
    );
  });
}
