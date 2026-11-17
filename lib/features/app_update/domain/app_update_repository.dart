import '../../../core/network/api_failure.dart';
import 'update_policy.dart';

abstract class AppUpdateRepository {
  Future<UpdatePolicy> check({required String platform, required int build});
  Future<UpdatePolicy?> cached();
  Future<void> cacheRequired(AppUpdateRequiredFailure failure);
}
