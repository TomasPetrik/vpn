sealed class ApiFailure {
  const ApiFailure(this.message);
  final String message;
}

class NetworkFailure extends ApiFailure {
  const NetworkFailure([super.message = 'network error']);
}

class ServerFailure extends ApiFailure {
  const ServerFailure(this.code, [super.message = 'server error']);
  final String code;
}

class UnauthorizedFailure extends ApiFailure {
  const UnauthorizedFailure([super.message = 'unauthorized']);
}

class AppUpdateRequiredFailure extends ApiFailure {
  const AppUpdateRequiredFailure({
    required this.updateUrl,
    required this.updateMessage,
    required this.minSupportedBuild,
    required this.latestBuild,
  }) : super(updateMessage);

  final String updateUrl;
  final String updateMessage;
  final int minSupportedBuild;
  final int latestBuild;
}
