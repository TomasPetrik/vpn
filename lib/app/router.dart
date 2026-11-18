import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/di/injection.dart';
import '../features/account/presentation/account_page.dart';
import '../features/app_update/presentation/app_update_cubit.dart';
import '../features/app_update/presentation/update_required_page.dart';
import '../features/debug/presentation/api_log_page.dart';
import '../features/device/presentation/bootstrap_cubit.dart';
import '../features/device/presentation/splash_page.dart';
import '../features/servers/presentation/server_info_cubit.dart';
import '../features/shell/presentation/main_shell.dart';
import '../features/vpn/presentation/home_page.dart';
import '../features/vpn/presentation/vpn_connect_cubit.dart';
import '../features/vpn/presentation/vpn_stats_page.dart';

GoRouter createRouter({
  required AppUpdateCubit appUpdateCubit,
  required BootstrapCubit bootstrapCubit,
  required ServerInfoCubit serverInfoCubit,
}) {
  final refresh = _MultiCubitListenable([appUpdateCubit, bootstrapCubit]);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final update = appUpdateCubit.state;
      final loc = state.matchedLocation;
      if (update is AppUpdateRequired) {
        return loc == '/update-required' ? null : '/update-required';
      }
      if (loc == '/update-required') {
        return '/';
      }
      if (loc == '/debug/api-log') {
        return null;
      }
      if (loc == '/') {
        final boot = bootstrapCubit.state;
        if (boot is BootstrapRegistered || boot is BootstrapOffline) {
          return '/home';
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => MainShell(
          navigationShell: navigationShell,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => MultiBlocProvider(
                  providers: [
                    BlocProvider.value(value: serverInfoCubit),
                    BlocProvider.value(value: appUpdateCubit),
                    BlocProvider.value(value: getIt<VpnConnectCubit>()),
                  ],
                  child: const HomePage(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stats',
                builder: (context, state) => BlocProvider.value(
                  value: getIt<VpnConnectCubit>(),
                  child: const VpnStatsPage(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/account',
                builder: (context, state) => const AccountPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/update-required',
        builder: (context, state) => BlocProvider.value(
          value: appUpdateCubit,
          child: const UpdateRequiredPage(),
        ),
      ),
      GoRoute(
        path: '/debug/api-log',
        builder: (context, state) => const ApiLogPage(),
      ),
    ],
  );
}

class _MultiCubitListenable extends ChangeNotifier {
  _MultiCubitListenable(List<BlocBase<dynamic>> cubits) {
    for (final cubit in cubits) {
      _subs.add(cubit.stream.listen((_) => notifyListeners()));
    }
  }

  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}
