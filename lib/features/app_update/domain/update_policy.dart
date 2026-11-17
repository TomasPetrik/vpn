import 'package:equatable/equatable.dart';

enum UpdateStatus { none, recommended, required }

class UpdatePolicy extends Equatable {
  const UpdatePolicy({
    required this.status,
    required this.minSupportedBuild,
    required this.latestBuild,
    this.updateUrl = '',
    this.message = '',
  });

  final UpdateStatus status;
  final int minSupportedBuild;
  final int latestBuild;
  final String updateUrl;
  final String message;

  factory UpdatePolicy.fromJson(Map<String, dynamic> json) {
    final status = switch ('${json['status']}') {
      'required' => UpdateStatus.required,
      'recommended' => UpdateStatus.recommended,
      _ => UpdateStatus.none,
    };
    return UpdatePolicy(
      status: status,
      minSupportedBuild: int.tryParse('${json['min_supported_build']}') ?? 0,
      latestBuild: int.tryParse('${json['latest_build']}') ?? 0,
      updateUrl: '${json['update_url'] ?? ''}',
      message: '${json['message'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'min_supported_build': minSupportedBuild,
        'latest_build': latestBuild,
        'update_url': updateUrl,
        'message': message,
      };

  @override
  List<Object?> get props =>
      [status, minSupportedBuild, latestBuild, updateUrl, message];
}
