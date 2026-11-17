import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'device_token';
  static const _installationKey = 'installation_id';

  Future<String?> readToken() => _storage.read(key: _tokenKey);
  Future<void> writeToken(String value) =>
      _storage.write(key: _tokenKey, value: value);
  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<String?> readInstallationId() => _storage.read(key: _installationKey);
  Future<void> writeInstallationId(String value) =>
      _storage.write(key: _installationKey, value: value);
}
