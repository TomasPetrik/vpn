import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../domain/app_update_repository.dart';
import '../domain/update_policy.dart';

sealed class AppUpdateState {
  const AppUpdateState();
}

class AppUpdateUnknown extends AppUpdateState {
  const AppUpdateUnknown();
}

class AppUpdateUpToDate extends AppUpdateState {
  const AppUpdateUpToDate();
}

class AppUpdateAvailable extends AppUpdateState {
  const AppUpdateAvailable(this.policy);
  final UpdatePolicy policy;
}

class AppUpdateRequired extends AppUpdateState {
  const AppUpdateRequired(this.policy);
  final UpdatePolicy policy;
}

class AppUpdateCubit extends Cubit<AppUpdateState> {
  AppUpdateCubit(this._repository, this._packageInfo)
      : super(const AppUpdateUnknown());

  final AppUpdateRepository _repository;
  final PackageInfo _packageInfo;

  Future<void> check() async {
    final platform =
        defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    final build = int.tryParse(_packageInfo.buildNumber) ?? 0;
    final policy = await _repository.check(platform: platform, build: build);
    switch (policy.status) {
      case UpdateStatus.required:
        emit(AppUpdateRequired(policy));
      case UpdateStatus.recommended:
        emit(AppUpdateAvailable(policy));
      case UpdateStatus.none:
        emit(const AppUpdateUpToDate());
    }
  }

  Future<void> applyCachedRequired() async {
    final cached = await _repository.cached();
    if (cached?.status == UpdateStatus.required) {
      emit(AppUpdateRequired(cached!));
    }
  }
}
