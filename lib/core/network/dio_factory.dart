import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import '../storage/secure_store.dart';
import 'api_failure.dart';
import 'api_traffic_log.dart';

typedef UpdateRequiredCallback = void Function(AppUpdateRequiredFailure failure);

class DioFactory {
  static Dio create({
    required AppConfig config,
    required PackageInfo packageInfo,
    required SecureStore secureStore,
    UpdateRequiredCallback? onUpdateRequired,
    ApiTrafficLog? trafficLog,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final platform = defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android';
          options.headers['X-App-Platform'] = platform;
          options.headers['X-App-Build'] = packageInfo.buildNumber;
          options.headers['X-App-Version'] = packageInfo.version;
          final token = await secureStore.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          if (trafficLog != null) {
            final headers = <String, String>{};
            options.headers.forEach((key, value) {
              if (value != null) {
                headers[key.toString()] = value.toString();
              }
            });
            final entry = trafficLog.start(
              method: options.method,
              uri: options.uri,
              requestHeaders: headers,
              requestBody: options.data,
            );
            options.extra['api_traffic_entry'] = entry;
          }

          handler.next(options);
        },
        onResponse: (response, handler) {
          final entry = response.requestOptions.extra['api_traffic_entry'];
          if (entry is ApiCallEntry && trafficLog != null) {
            trafficLog.complete(
              entry,
              statusCode: response.statusCode,
              responseBody: response.data,
            );
          }
          handler.next(response);
        },
        onError: (error, handler) {
          final entry = error.requestOptions.extra['api_traffic_entry'];
          if (entry is ApiCallEntry && trafficLog != null) {
            trafficLog.complete(
              entry,
              statusCode: error.response?.statusCode,
              responseBody: error.response?.data,
              errorMessage: error.message,
            );
          }

          final response = error.response;
          if (response?.statusCode == 426) {
            final data = response?.data;
            Map<String, dynamic>? update;
            if (data is Map<String, dynamic>) {
              final raw = data['update'];
              if (raw is Map<String, dynamic>) {
                update = raw;
              }
            }
            final failure = AppUpdateRequiredFailure(
              updateUrl: '${update?['update_url'] ?? ''}',
              updateMessage:
                  '${update?['message'] ?? 'Please update PetrikVPN.'}',
              minSupportedBuild:
                  int.tryParse('${update?['min_supported_build'] ?? 0}') ?? 0,
              latestBuild: int.tryParse('${update?['latest_build'] ?? 0}') ?? 0,
            );
            onUpdateRequired?.call(failure);
          }
          handler.next(error);
        },
      ),
    );
    return dio;
  }
}
