import 'package:equatable/equatable.dart';

class DeviceRegistration extends Equatable {
  const DeviceRegistration({
    required this.userId,
    required this.deviceId,
    this.created = false,
  });

  final String userId;
  final String deviceId;
  final bool created;

  @override
  List<Object?> get props => [userId, deviceId, created];
}
