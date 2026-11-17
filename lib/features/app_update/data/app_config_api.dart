import 'package:dio/dio.dart';

class AppConfigApi {
  AppConfigApi(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> fetchConfig({
    required String platform,
    required int build,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/app/config',
      queryParameters: {'platform': platform, 'build': build},
    );
    return response.data ?? {};
  }
}
