import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/secure_store.dart';
import '../domain/device_registration.dart';
import '../domain/device_repository.dart';
import 'device_api.dart';
import 'device_info_source.dart';

class DeviceRepositoryImpl implements DeviceRepository {
  DeviceRepositoryImpl({
    required this.api,
    required this.secureStore,
    required this.deviceInfo,
    required this.packageInfo,
  });

  final DeviceApi api;
  final SecureStore secureStore;
  final DeviceInfoSource deviceInfo;
  final PackageInfo packageInfo;

  @override
  Future<DeviceRegistration> register() async {
    var installationId = await secureStore.readInstallationId();
    if (installationId == null || installationId.isEmpty) {
      installationId = const Uuid().v4();
      await secureStore.writeInstallationId(installationId);
    }

    final info = await deviceInfo.collect();
    final body = <String, dynamic>{
      'installation_id': installationId,
      'device_identifier': info.deviceIdentifier,
      'platform': info.platform,
      'device': {
        'manufacturer': info.manufacturer,
        'model': info.model,
        'os_version': info.osVersion,
        'is_physical_device': info.isPhysicalDevice,
      },
      'app': {
        'version': packageInfo.version,
        'build': packageInfo.buildNumber,
      },
    };

    final data = await api.register(body);
    final token = data['device_token'];
    if (token is String && token.isNotEmpty) {
      await secureStore.writeToken(token);
    }

    return DeviceRegistration(
      userId: '${data['user_id']}',
      deviceId: '${data['device_id']}',
      created: data['created'] == true,
    );
  }
}
