import 'vpn_server.dart';

abstract class ServersRepository {
  Future<List<VpnServer>> list();
}
