import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../core/di/injection.dart';
import '../features/app_update/presentation/app_update_cubit.dart';
import '../features/device/presentation/bootstrap_cubit.dart';
import '../features/servers/presentation/server_info_cubit.dart';
import 'router.dart';

Future<AppBootstrap> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();

  final appUpdateCubit = getIt<AppUpdateCubit>();
  final bootstrapCubit = getIt<BootstrapCubit>();
  final serverInfoCubit = getIt<ServerInfoCubit>();

  await appUpdateCubit.applyCachedRequired();
  await appUpdateCubit.check();
  if (appUpdateCubit.state is! AppUpdateRequired) {
    await bootstrapCubit.start();
  }

  final router = createRouter(
    appUpdateCubit: appUpdateCubit,
    bootstrapCubit: bootstrapCubit,
    serverInfoCubit: serverInfoCubit,
  );

  WidgetsBinding.instance.addObserver(_LifecycleObserver(appUpdateCubit));

  return AppBootstrap(
    router: router,
    appUpdateCubit: appUpdateCubit,
    bootstrapCubit: bootstrapCubit,
  );
}

class AppBootstrap {
  AppBootstrap({
    required this.router,
    required this.appUpdateCubit,
    required this.bootstrapCubit,
  });

  final GoRouter router;
  final AppUpdateCubit appUpdateCubit;
  final BootstrapCubit bootstrapCubit;
}

class _LifecycleObserver with WidgetsBindingObserver {
  _LifecycleObserver(this._cubit);

  final AppUpdateCubit _cubit;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cubit.check();
    }
  }
}
