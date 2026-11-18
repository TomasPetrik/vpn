import 'package:dio/dio.dart';

class DeviceApi {
  DeviceApi(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> register(Map<String, dynamic> body) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/devices/register',
      data: body,
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> me() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/v1/me');
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> upsertPeer({required String publicKey}) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/v1/devices/me/peer',
      data: {'public_key': publicKey},
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> getPeer() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/devices/me/peer',
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> usage({required String range}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/devices/me/usage',
      queryParameters: {'range': range},
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> submitDiagnostics(
    Map<String, dynamic> body,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/devices/me/diagnostics',
      data: body,
    );
    return response.data ?? {};
  }
}
