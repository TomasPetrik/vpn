import '../../vpn/domain/usage_series.dart';
import 'device_registration.dart';
import 'device_session.dart';
import 'public_network_info.dart';
import 'vpn_peer_config.dart';

abstract class DeviceRepository {
  Future<DeviceRegistration> register({bool clearBearer = false});

  /// Ensures a valid device session (re-registers if the token is missing/401).
  Future<DeviceSession> ensureSession();

  Future<DeviceSession> me();

  Future<VpnPeerConfig> upsertPeer({required String publicKey});

  Future<VpnPeerConfig?> getPeer();

  /// Backend peer_stats daily/hourly buckets for this device.
  Future<UsageSeries> usageSeries({required String range});

  /// Current public WAN IP (API-observed client IP, with public fallback).
  Future<String?> currentPublicIp();

  /// Current public WAN IP + country (for local-connection UI).
  Future<PublicNetworkInfo> currentPublicNetwork();
}
