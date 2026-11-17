class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  final String apiBaseUrl;

  static AppConfig fromEnvironment() {
    const url = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8090',
    );
    return AppConfig(apiBaseUrl: url);
  }
}
