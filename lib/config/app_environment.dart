/// Build-time environment selector for the web app.
///
/// The active environment is chosen at build time with a `--dart-define`:
///
/// ```sh
/// flutter build web --release --pwa-strategy=none --dart-define=ENV=prod
/// flutter build web --release --pwa-strategy=none --dart-define=ENV=uat
/// ```
///
/// Defaults to [AppEnvironment.uat] when `ENV` is unset (e.g. local `flutter
/// run`) so a stray build never accidentally targets production.
///
/// Each environment maps to a separate Firebase Hosting project:
///   - prod -> Sawad-Loan-Universal-Prod
///   - uat  -> Sawad-Loan-Universal-UAT
///
/// There is no backend/API wiring yet (see CLAUDE.md). When one is added, put
/// the per-environment base URLs / keys on [AppEnvironment] and read them via
/// [AppEnvironment.current].
library;

enum AppEnvironment {
  prod(
    name: 'prod',
    firebaseProjectAlias: 'prod',
  ),
  uat(
    name: 'uat',
    firebaseProjectAlias: 'uat',
  );

  const AppEnvironment({
    required this.name,
    required this.firebaseProjectAlias,
  });

  /// Short identifier, e.g. `prod` / `uat`.
  final String name;

  /// Alias used in `.firebaserc` (`firebase deploy -P <alias>`).
  final String firebaseProjectAlias;

  /// The `ENV` value baked in at build time. Empty for local runs.
  static const String _raw = String.fromEnvironment('ENV');

  /// The active environment for this build. Falls back to [uat].
  static final AppEnvironment current = _parse(_raw);

  static AppEnvironment _parse(String value) {
    switch (value.trim().toLowerCase()) {
      case 'prod':
      case 'production':
        return AppEnvironment.prod;
      case 'uat':
      case 'staging':
        return AppEnvironment.uat;
      default:
        return AppEnvironment.uat;
    }
  }

  bool get isProd => this == AppEnvironment.prod;
  bool get isUat => this == AppEnvironment.uat;
}
