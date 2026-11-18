import 'package:equatable/equatable.dart';

class DeviceSession extends Equatable {
  const DeviceSession({
    required this.userId,
    required this.deviceId,
    this.clientIp,
    this.clientCountry,
  });

  final String userId;
  final String deviceId;

  /// Public IP as seen by the API (assigned WAN IP when not on VPN).
  final String? clientIp;

  /// ISO 3166-1 alpha-2 for [clientIp], when GeoIP is available.
  final String? clientCountry;

  factory DeviceSession.fromJson(Map<String, dynamic> json) {
    final rawIp = json['client_ip']?.toString().trim();
    final rawCountry = json['client_country']?.toString().trim().toUpperCase();
    return DeviceSession(
      userId: '${json['user_id']}',
      deviceId: '${json['device_id']}',
      clientIp: (rawIp == null || rawIp.isEmpty) ? null : rawIp,
      clientCountry: (rawCountry == null ||
              rawCountry.isEmpty ||
              rawCountry.length != 2)
          ? null
          : rawCountry,
    );
  }

  @override
  List<Object?> get props => [userId, deviceId, clientIp, clientCountry];
}
