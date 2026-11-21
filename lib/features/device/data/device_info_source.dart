import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:mobile_device_identifier/mobile_device_identifier.dart';

class CollectedDeviceInfo {
  const CollectedDeviceInfo({
    required this.platform,
    this.deviceIdentifier,
    this.manufacturer,
    this.model,
    this.osVersion,
    this.isPhysicalDevice = true,
  });

  final String platform;
  final String? deviceIdentifier;
  final String? manufacturer;
  final String? model;
  final String? osVersion;
  final bool isPhysicalDevice;
}

class DeviceInfoSource {
  DeviceInfoSource({
    MobileDeviceIdentifier? mobileDeviceIdentifier,
    DeviceInfoPlugin? deviceInfoPlugin,
  })  : _mobileDeviceIdentifier =
            mobileDeviceIdentifier ?? MobileDeviceIdentifier(),
        _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin();

  final MobileDeviceIdentifier _mobileDeviceIdentifier;
  final DeviceInfoPlugin _deviceInfoPlugin;

  Future<CollectedDeviceInfo> collect() async {
    if (Platform.isIOS) {
      final info = await _deviceInfoPlugin.iosInfo;
      final deviceIdentifier = await _resolveDeviceIdentifier(
        fallback: info.identifierForVendor,
      );
      return CollectedDeviceInfo(
        platform: 'ios',
        deviceIdentifier: deviceIdentifier,
        manufacturer: 'Apple',
        model: info.utsname.machine,
        osVersion: info.systemVersion,
        isPhysicalDevice: info.isPhysicalDevice,
      );
    }

    final info = await _deviceInfoPlugin.androidInfo;
    final deviceIdentifier = await _resolveDeviceIdentifier(
      fallback: info.id,
    );
    return CollectedDeviceInfo(
      platform: 'android',
      deviceIdentifier: deviceIdentifier,
      manufacturer: info.manufacturer,
      model: info.model,
      osVersion: info.version.release,
      isPhysicalDevice: info.isPhysicalDevice,
    );
  }

  /// Prefer [mobile_device_identifier] (Widevine / Keychain+IFV — same approach
  /// as mobile-flutter-merchant and wow_swift). Fall back to platform IDs from
  /// device_info_plus when the plugin returns null (common on some emulators).
  Future<String?> _resolveDeviceIdentifier({String? fallback}) async {
    try {
      final raw = await _mobileDeviceIdentifier.getDeviceId();
      final trimmed = raw?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    } catch (_) {
      // Fall through to platform identifier.
    }

    final trimmedFallback = fallback?.trim();
    if (trimmedFallback != null &&
        trimmedFallback.isNotEmpty &&
        trimmedFallback.toLowerCase() != 'unknown' &&
        trimmedFallback != '00000000-0000-0000-0000-000000000000') {
      return trimmedFallback;
    }
    return null;
  }
}
