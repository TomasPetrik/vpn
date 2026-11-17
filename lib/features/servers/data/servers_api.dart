import 'package:dio/dio.dart';

class ServersApi {
  ServersApi(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> list() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/v1/servers');
    return response.data ?? {};
  }
}
