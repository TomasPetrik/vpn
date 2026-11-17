import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_failure.dart';
import '../domain/app_update_repository.dart';
import '../domain/update_policy.dart';
import 'app_config_api.dart';

class AppUpdateRepositoryImpl implements AppUpdateRepository {
  AppUpdateRepositoryImpl({required this.api, required this.prefs});

  final AppConfigApi api;
  final SharedPreferences prefs;

  static const _cacheKey = 'update_policy_cache';

  @override
  Future<UpdatePolicy> check({
    required String platform,
    required int build,
  }) async {
    try {
      final data = await api.fetchConfig(platform: platform, build: build);
      final update = data['update'];
      final policy = UpdatePolicy.fromJson(
        update is Map<String, dynamic> ? update : <String, dynamic>{},
      );
      await prefs.setString(_cacheKey, jsonEncode(policy.toJson()));
      return policy;
    } catch (_) {
      final cachedPolicy = await cached();
      if (cachedPolicy != null) {
        return cachedPolicy;
      }
      return const UpdatePolicy(
        status: UpdateStatus.none,
        minSupportedBuild: 0,
        latestBuild: 0,
      );
    }
  }

  @override
  Future<UpdatePolicy?> cached() async {
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final map = jsonDecode(raw);
    if (map is! Map<String, dynamic>) {
      return null;
    }
    return UpdatePolicy.fromJson(map);
  }

  @override
  Future<void> cacheRequired(AppUpdateRequiredFailure failure) async {
    final policy = UpdatePolicy(
      status: UpdateStatus.required,
      minSupportedBuild: failure.minSupportedBuild,
      latestBuild: failure.latestBuild,
      updateUrl: failure.updateUrl,
      message: failure.updateMessage,
    );
    await prefs.setString(_cacheKey, jsonEncode(policy.toJson()));
  }
}
