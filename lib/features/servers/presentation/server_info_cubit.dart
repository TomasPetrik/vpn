import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/servers_repository.dart';
import '../domain/vpn_server.dart';

sealed class ServerInfoState {
  const ServerInfoState();
}

class ServerInfoLoading extends ServerInfoState {
  const ServerInfoLoading();
}

class ServerInfoLoaded extends ServerInfoState {
  const ServerInfoLoaded(this.servers);
  final List<VpnServer> servers;
}

class ServerInfoError extends ServerInfoState {
  const ServerInfoError(this.message);
  final String message;
}

class ServerInfoCubit extends Cubit<ServerInfoState> {
  ServerInfoCubit(this._repository) : super(const ServerInfoLoading());

  final ServersRepository _repository;

  /// Loads servers once. Pass [force] to refresh explicitly.
  Future<void> load({bool force = false}) async {
    if (!force && state is ServerInfoLoaded) {
      return;
    }
    emit(const ServerInfoLoading());
    try {
      final servers = await _repository.list();
      emit(ServerInfoLoaded(servers));
    } catch (e) {
      emit(ServerInfoError(e.toString()));
    }
  }
}
