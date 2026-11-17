import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import '../storage/secure_store.dart';
import 'api_failure.dart';

typedef UpdateRequiredCallback = void Function(AppUpdateRequiredFailure failure);

class DioFactory {
  static Dio create({
    required AppConfig config,
    required PackageInfo packageInfo,
    required SecureStore secureStore,
    UpdateRequiredCallback? onUpdateRequired,
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
          handler.next(options);
        },
        onError: (error, handler) {
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
