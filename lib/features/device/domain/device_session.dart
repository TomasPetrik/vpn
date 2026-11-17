import 'package:equatable/equatable.dart';

class DeviceSession extends Equatable {
  const DeviceSession({
    required this.userId,
    required this.deviceId,
  });

  final String userId;
  final String deviceId;

  factory DeviceSession.fromJson(Map<String, dynamic> json) {
    return DeviceSession(
      userId: '${json['user_id']}',
      deviceId: '${json['device_id']}',
    );
  }

  @override
  List<Object?> get props => [userId, deviceId];
}
