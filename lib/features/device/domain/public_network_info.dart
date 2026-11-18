import 'package:equatable/equatable.dart';

/// Observed public WAN endpoint (IP + optional country).
class PublicNetworkInfo extends Equatable {
  const PublicNetworkInfo({this.ip, this.countryCode});

  final String? ip;
  final String? countryCode;

  @override
  List<Object?> get props => [ip, countryCode];
}
