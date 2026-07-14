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

/// Build-time web version stamp, set via `--dart-define=WEB_VERSION` (CI passes
/// the GitHub Actions run number). Used to spot a **stale cached web build**:
/// it's logged to the browser console on every startup and stored on
/// `AppState.webVersion`, so you can see which build a client is actually
/// running (the native WebView host can read it from the console too).
///
/// Defaults to `'0'` for local/dev builds where `WEB_VERSION` isn't passed.
const String kWebVersion = String.fromEnvironment(
  'WEB_VERSION',
  defaultValue: '0',
);

/// Base URL of the **NDID local-node API** (the node wrapper from the NDID
/// Postman collection, hosted on the dev gateway). Override at build time:
///
/// ```sh
/// flutter build web ... --dart-define=NDID_API_BASE=http://localhost:7088
/// ```
///
/// Used by `lib/services/ndid_api.dart`, and only when running inside the
/// native host (plain-browser builds keep the simulated NDID flow). No
/// trailing slash — paths are appended as `/idp/list`, `/rp/verify`, ….
const String kNdidApiBase = String.fromEnvironment(
  'NDID_API_BASE',
  defaultValue: 'https://dev.swpfin.com/dap',
);

/// API key for the NDID local-node API, sent as an `X-API-Key` header on
/// every request (the node's collection-level auth). Overridable per build
/// with `--dart-define=NDID_API_KEY=...`; empty disables the header.
const String kNdidApiKey = String.fromEnvironment(
  'NDID_API_KEY',
  defaultValue: 'ndid_Gl_dI1z8JCeHebNbnyzICvpCep3KHLYY1oeDHjfNTXI',
);

enum AppEnvironment {
  prod(
    name: 'prod',
    firebaseProjectAlias: 'prod',
    mobileApiBase: 'https://mobile-api.swpfin.com',
    srisawadHeader: 'x1',
  ),
  uat(
    name: 'uat',
    firebaseProjectAlias: 'uat',
    mobileApiBase: 'https://dev.swpfin.com:7076',
    srisawadHeader: '', // UAT doesn't require the x-srisawad header
  );

  const AppEnvironment({
    required this.name,
    required this.firebaseProjectAlias,
    required this.mobileApiBase,
    required this.srisawadHeader,
  });

  /// Short identifier, e.g. `prod` / `uat`.
  final String name;

  /// Alias used in `.firebaserc` (`firebase deploy -P <alias>`).
  final String firebaseProjectAlias;

  /// Base URL of the srisawad **mobile API** (customer profile + addresses —
  /// see `api_data/api1.md` and `lib/services/user_api.dart`). No trailing
  /// slash.
  final String mobileApiBase;

  /// Value for the `x-srisawad` request header the mobile API expects; empty
  /// means "don't send the header" (UAT).
  final String srisawadHeader;

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
