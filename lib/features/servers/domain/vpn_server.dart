import 'package:equatable/equatable.dart';

class VpnServer extends Equatable {
  const VpnServer({
    required this.id,
    required this.name,
    this.countryCode,
    this.city,
    this.status = 'online',
  });

  final String id;
  final String name;
  final String? countryCode;
  final String? city;
  final String status;

  factory VpnServer.fromJson(Map<String, dynamic> json) {
    return VpnServer(
      id: '${json['id']}',
      name: '${json['name']}',
      countryCode: json['country_code']?.toString(),
      city: json['city']?.toString(),
      status: '${json['status'] ?? 'online'}',
    );
  }

  @override
  List<Object?> get props => [id, name, countryCode, city, status];
}
