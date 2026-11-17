import 'package:dio/dio.dart';

class HealthApi {
  HealthApi(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> healthz() async {
    final response = await _dio.get<Map<String, dynamic>>('/healthz');
    return response.data ?? {};
  }
}
