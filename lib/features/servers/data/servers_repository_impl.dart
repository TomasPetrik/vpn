import '../domain/servers_repository.dart';
import '../domain/vpn_server.dart';
import 'servers_api.dart';

class ServersRepositoryImpl implements ServersRepository {
  ServersRepositoryImpl({required this.api});

  final ServersApi api;

  @override
  Future<List<VpnServer>> list() async {
    final data = await api.list();
    final servers = data['servers'];
    if (servers is! List) {
      return const [];
    }
    return servers
        .whereType<Map>()
        .map((e) => VpnServer.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
