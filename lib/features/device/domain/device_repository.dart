import 'device_registration.dart';

abstract class DeviceRepository {
  Future<DeviceRegistration> register();
}
