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

/// **Fallback** base URL of the **NDID local-node API** (the node wrapper from
/// the NDID Postman collection, hosted on the dev gateway). Override at build
/// time:
///
/// ```sh
/// flutter build web ... --dart-define=NDID_API_BASE=http://localhost:7088
/// ```
///
/// Used by `lib/services/ndid_api.dart`, and only when running inside the
/// native host (plain-browser builds keep the simulated NDID flow). No
/// trailing slash — paths are appended as `/idp/list`, `/rp/verify`, ….
///
/// ⚠ **This is no longer the primary source.** `NdidApi.baseUrl()` prefers
/// `api_url['ndid_url_base']` from the Firestore runtime config, which is
/// per-project and needs no rebuild; this value is what it degrades to when
/// that document can't be read or omits the key.
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

// Removed 2026-07-31: `kNdidTestThaiId` / `NDID_TEST_THAI_ID`.
//
// It made non-prod builds run NDID against a fixed test id (`1234567890123`)
// instead of the applicant, because the DAP uat node had a registered identity
// for only that one Thai ID. The uat NDID gateway now carries real identities
// (`api_url.ndid_url_base`), so `PLoanFlow.ndidThaiId` is the customer's own id
// in every environment and the scaffolding — plus its prod-only gate — is gone.
//
// Passing `--dart-define=NDID_TEST_THAI_ID=...` is now silently ignored; drop it
// from any build script that still sets it.

/// Base URL of the **P-Loan save API** — `POST <base>/SavePloanContract`, the
/// endpoint a completed P-Loan application is filed to.
///
/// ```sh
/// flutter build web ... --dart-define=P_LOAN_SAVE_API_BASE=https://...
/// ```
///
/// No trailing slash. Separate from the mobile API: it is a different host and
/// port, with its own auth scheme (see [kPLoanSaveApiAuth]).
const String kPLoanSaveApiBase = String.fromEnvironment(
  'P_LOAN_SAVE_API_BASE',
  defaultValue: 'https://dev.swpfin.com:8082',
);

/// `Authorization` header value for the P-Loan save API — HTTP Basic.
///
/// ```sh
/// flutter build web ... --dart-define=P_LOAN_SAVE_API_AUTH='Basic <base64>'
/// ```
///
/// **⚠ This is a shared service credential in a public web bundle.** Anyone can
/// download `main.dart.js` and read it, exactly as with [kNdidApiKey] — a
/// `--dart-define` changes where the value comes from, not who can see it. The
/// only real fixes are server-side: proxy this endpoint behind the mobile API
/// (which already fronts the app), or issue a credential scoped to this client
/// that can be rotated and rate-limited on its own. Until then, treat the
/// account as compromised-by-design and give it the narrowest possible rights.
const String kPLoanSaveApiAuth = String.fromEnvironment(
  'P_LOAN_SAVE_API_AUTH',
  defaultValue: 'Basic Y2RwYXBpcHJvZDpQQHNzdzByZDEyMyNAITIwMjU=',
);

/// Serve the P-Loan application flow from fixtures instead of calling the
/// mobile API.
///
/// **Off by default — the flow runs against the live API.** Kept as a switch
/// for demoing without a backend, or for reproducing a screen state the API
/// can't currently produce:
///
/// ```sh
/// flutter build web ... --dart-define=P_LOAN_MOCK=true
/// ```
///
/// Everything it affects lives behind one guard per method in
/// `services/p_loan_api.dart`, and the fixtures are in
/// `p_loan/application/models/p_loan_mock.dart` (also used by the tests). While
/// it is on, every screen in the flow shows a banner so fixture data can't be
/// mistaken for real.
const bool kPLoanUseMockData = bool.fromEnvironment(
  'P_LOAN_MOCK',
  defaultValue: false,
);

/// Firestore path of the runtime-config document read at startup
/// (`services/app_config_api.dart`). Overridable so the config can be moved to
/// a document with narrower security rules without a code change:
///
/// ```sh
/// flutter build web ... --dart-define=APP_CONFIG_PATH=application/public_config
/// ```
///
/// Must be a `collection/document` pair.
const String kAppConfigPath = String.fromEnvironment(
  'APP_CONFIG_PATH',
  defaultValue: 'application/public_config',
);

enum AppEnvironment {
  prod(
    name: 'prod',
    firebaseProjectAlias: 'prod',
    firebaseProjectId: 'sawad-loan-universal-prod',
    // No web app registered on prod yet — register one and paste its key here
    // to enable the anonymous read of the runtime config. Empty means the app
    // skips sign-in and uses the compile-time endpoint below.
    firebaseApiKey: '',
    mobileApiBase: 'https://mobile-api.swpfin.com',
    srisawadHeader: 'x1',
  ),
  uat(
    name: 'uat',
    firebaseProjectAlias: 'uat',
    firebaseProjectId: 'sawad-loan-universal-uat',
    firebaseApiKey: 'AIzaSyDty7ZRY-LS1K31L8w2inZsRyE7wOccFEI',
    mobileApiBase: 'https://dev.swpfin.com:7076',
    srisawadHeader: '', // UAT doesn't require the x-srisawad header
  );

  const AppEnvironment({
    required this.name,
    required this.firebaseProjectAlias,
    required this.firebaseProjectId,
    required this.firebaseApiKey,
    required this.mobileApiBase,
    required this.srisawadHeader,
  });

  /// Short identifier, e.g. `prod` / `uat`.
  final String name;

  /// Alias used in `.firebaserc` (`firebase deploy -P <alias>`).
  final String firebaseProjectAlias;

  /// Firebase project id, used to build the Firestore REST URL for the runtime
  /// config document. Must match the `.firebaserc` alias above.
  final String firebaseProjectId;

  /// Firebase **web API key** for anonymous sign-in (`FirebaseAuthRest`).
  ///
  /// Not a secret: it identifies the project to Google's endpoints, is expected
  /// to be public in a web client, and grants nothing on its own — access is
  /// decided entirely by the Firestore rules. Empty disables sign-in, in which
  /// case the config read is skipped and [mobileApiBase] is used.
  final String firebaseApiKey;

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
