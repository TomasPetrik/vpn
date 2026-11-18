import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/secure_store.dart';
import '../../vpn/domain/usage_series.dart';
import '../domain/device_registration.dart';
import '../domain/device_repository.dart';
import '../domain/device_session.dart';
import '../domain/public_network_info.dart';
import '../domain/vpn_peer_config.dart';
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
  Future<DeviceRegistration> register({bool clearBearer = false}) async {
    if (clearBearer) {
      await secureStore.clearToken();
    }

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
    } else {
      final existing = await secureStore.readToken();
      if (existing == null || existing.isEmpty) {
        if (!clearBearer) {
          return register(clearBearer: true);
        }
        throw StateError('register returned no device_token');
      }
    }

    return DeviceRegistration(
      userId: '${data['user_id']}',
      deviceId: '${data['device_id']}',
      created: data['created'] == true,
    );
  }

  @override
  Future<DeviceSession> ensureSession() async {
    final existing = await secureStore.readToken();
    if (existing != null && existing.isNotEmpty) {
      try {
        return await me();
      } on DioException catch (e) {
        if (e.response?.statusCode != 401 && e.response?.statusCode != 403) {
          rethrow;
        }
      }
    }
    await register(clearBearer: true);
    return me();
  }

  @override
  Future<DeviceSession> me() async {
    final data = await api.me();
    return DeviceSession.fromJson(data);
  }

  @override
  Future<VpnPeerConfig> upsertPeer({required String publicKey}) async {
    final data = await api.upsertPeer(publicKey: publicKey);
    return VpnPeerConfig.fromJson(data);
  }

  @override
  Future<VpnPeerConfig?> getPeer() async {
    try {
      final data = await api.getPeer();
      return VpnPeerConfig.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<UsageSeries> usageSeries({required String range}) async {
    await ensureSession();
    final data = await api.usage(range: range);
    return UsageSeries.fromJson(data);
  }

  @override
  Future<String?> currentPublicIp() async {
    final info = await currentPublicNetwork();
    return info.ip;
  }

  @override
  Future<PublicNetworkInfo> currentPublicNetwork() async {
    try {
      await ensureSession();
      final session = await me();
      final ip = session.clientIp?.trim();
      if (ip != null && ip.isNotEmpty) {
        final country = session.clientCountry;
        if (country != null && country.isNotEmpty) {
          return PublicNetworkInfo(ip: ip, countryCode: country);
        }
        final resolved = await _countryForIp(ip);
        return PublicNetworkInfo(ip: ip, countryCode: resolved);
      }
    } catch (_) {
      // Fall through to public echo services.
    }

    try {
      final response = await Dio().get<Map<String, dynamic>>(
        'https://api.country.is/',
      );
      final data = response.data;
      final ip = data?['ip']?.toString().trim();
      final country = data?['country']?.toString().trim().toUpperCase();
      if (ip != null && ip.isNotEmpty) {
        return PublicNetworkInfo(
          ip: ip,
          countryCode: (country != null && country.length == 2) ? country : null,
        );
      }
    } catch (_) {}

    try {
      final response = await Dio().get<String>('https://api.ipify.org');
      final ip = response.data?.trim();
      if (ip != null && ip.isNotEmpty) {
        final country = await _countryForIp(ip);
        return PublicNetworkInfo(ip: ip, countryCode: country);
      }
    } catch (_) {}

    return const PublicNetworkInfo();
  }

  Future<String?> _countryForIp(String ip) async {
    try {
      final response = await Dio().get<Map<String, dynamic>>(
        'https://api.country.is/$ip',
      );
      final country = response.data?['country']?.toString().trim().toUpperCase();
      if (country != null && country.length == 2) {
        return country;
      }
    } catch (_) {}
    return null;
  }
}
