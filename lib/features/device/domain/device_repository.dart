import 'device_registration.dart';
import 'device_session.dart';
import 'vpn_peer_config.dart';

abstract class DeviceRepository {
  Future<DeviceRegistration> register();

  Future<DeviceSession> me();

  Future<VpnPeerConfig> upsertPeer({required String publicKey});

  Future<VpnPeerConfig?> getPeer();
}
