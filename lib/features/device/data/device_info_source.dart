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
  Future<CollectedDeviceInfo> collect() async {
    String? deviceIdentifier;
    try {
      final raw = await MobileDeviceIdentifier().getDeviceId();
      if (raw != null && raw.trim().isNotEmpty) {
        deviceIdentifier = raw.trim();
      }
    } catch (_) {
      deviceIdentifier = null;
    }

    final plugin = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      return CollectedDeviceInfo(
        platform: 'ios',
        deviceIdentifier: deviceIdentifier,
        manufacturer: 'Apple',
        model: info.utsname.machine,
        osVersion: info.systemVersion,
        isPhysicalDevice: info.isPhysicalDevice,
      );
    }

    final info = await plugin.androidInfo;
    return CollectedDeviceInfo(
      platform: 'android',
      deviceIdentifier: deviceIdentifier,
      manufacturer: info.manufacturer,
      model: info.model,
      osVersion: info.version.release,
      isPhysicalDevice: info.isPhysicalDevice,
    );
  }
}
