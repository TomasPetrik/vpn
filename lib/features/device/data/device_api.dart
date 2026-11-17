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
}
