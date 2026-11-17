class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.isDevMode,
  });

  final String apiBaseUrl;
  final bool isDevMode;

  static AppConfig fromEnvironment() {
    const url = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://vpn.radarcut.com',
    );
    const devMode = bool.fromEnvironment('DEV_MODE', defaultValue: false);
    return AppConfig(apiBaseUrl: url, isDevMode: devMode);
  }
}
