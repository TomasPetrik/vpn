import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/app_update/data/app_config_api.dart';
import '../../features/app_update/data/app_update_repository_impl.dart';
import '../../features/app_update/domain/app_update_repository.dart';
import '../../features/app_update/presentation/app_update_cubit.dart';
import '../../features/device/data/device_api.dart';
import '../../features/device/data/device_info_source.dart';
import '../../features/device/data/device_repository_impl.dart';
import '../../features/device/domain/device_repository.dart';
import '../../features/device/presentation/bootstrap_cubit.dart';
import '../../features/health/data/health_api.dart';
import '../../features/servers/data/servers_api.dart';
import '../../features/servers/data/servers_repository_impl.dart';
import '../../features/servers/domain/servers_repository.dart';
import '../../features/servers/presentation/server_info_cubit.dart';
import '../config/app_config.dart';
import '../network/api_failure.dart';
import '../network/api_traffic_log.dart';
import '../network/dio_factory.dart';
import '../storage/secure_store.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  final config = AppConfig.fromEnvironment();
  final prefs = await SharedPreferences.getInstance();
  final packageInfo = await PackageInfo.fromPlatform();
  final secureStore = SecureStore();
  final trafficLog = ApiTrafficLog();

  getIt
    ..registerSingleton(config)
    ..registerSingleton(prefs)
    ..registerSingleton(packageInfo)
    ..registerSingleton(secureStore)
    ..registerSingleton(trafficLog);

  final updateApi = AppConfigApi(
    DioFactory.create(
      config: config,
      packageInfo: packageInfo,
      secureStore: secureStore,
      trafficLog: config.isDevMode ? trafficLog : null,
    ),
  );
  final updateRepo = AppUpdateRepositoryImpl(api: updateApi, prefs: prefs);
  getIt.registerSingleton<AppUpdateRepository>(updateRepo);

  late final AppUpdateCubit appUpdateCubit;
  final dio = DioFactory.create(
    config: config,
    packageInfo: packageInfo,
    secureStore: secureStore,
    trafficLog: config.isDevMode ? trafficLog : null,
    onUpdateRequired: (AppUpdateRequiredFailure failure) async {
      await updateRepo.cacheRequired(failure);
      await appUpdateCubit.applyCachedRequired();
    },
  );

  getIt
    ..registerSingleton(dio)
    ..registerSingleton(DeviceApi(dio))
    ..registerSingleton(ServersApi(dio))
    ..registerSingleton(HealthApi(dio))
    ..registerSingleton(DeviceInfoSource())
    ..registerSingleton<DeviceRepository>(
      DeviceRepositoryImpl(
        api: getIt(),
        secureStore: secureStore,
        deviceInfo: getIt(),
        packageInfo: packageInfo,
      ),
    )
    ..registerSingleton<ServersRepository>(
      ServersRepositoryImpl(api: getIt()),
    );

  appUpdateCubit = AppUpdateCubit(updateRepo, packageInfo);
  getIt
    ..registerSingleton(appUpdateCubit)
    ..registerFactory(() => BootstrapCubit(getIt()))
    ..registerFactory(() => ServerInfoCubit(getIt()));
}
