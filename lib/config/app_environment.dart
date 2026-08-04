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

/// Optional `request_type` for `POST /rp/verify`. **Empty means omit the field**,
/// which is the default.
///
/// The field is not required by either gateway — verified 2026-07-31 by posting
/// without it to both, which got past validation to `20005 - No IdP found` in
/// each case. UAT does not use it, so we don't send it.
///
/// It stays configurable because when it *is* sent it must match the gateway:
/// each NDID environment publishes its own list at `GET /request-types`
/// (`NdidApi.listRequestTypes()`), the sets do **not** overlap, and a value
/// outside them is refused with `20091 - Invalid request type`:
///
/// | Gateway | Valid values |
/// | --- | --- |
/// | `dev.swpfin.com/dap` (SIT) | `Authen Only`, `TestRequestType`, `dContract` |
/// | `uat.ndid.srisawadpower.com` | `dsign.accountopening`, `dsign.dcontract`, `dsign.dcontract.public`, `easyconnext.lineoa`, `idpconnext.thaid` |
///
/// That mismatch is exactly what broke the hop earlier the same day: the body
/// carried a hardcoded `'Authen Only'`, which SIT accepts and uat rejects.
///
/// Overridable per build, and at runtime by `ndid_request_type` in the Firestore
/// config, so it can track whatever [kNdidApiBase] / `ndid_url_base` points at:
///
/// ```sh
/// flutter build web ... --dart-define=NDID_REQUEST_TYPE='Authen Only'   # SIT
/// ```
///
/// ⚠ Setting one is not free: `request_type` names an NDID service, so it can
/// change the consent wording the IdP shows and how the request is billed. Get
/// the value from the DAP/NDID team rather than picking a plausible-looking one.
const String kNdidRequestType = String.fromEnvironment(
  'NDID_REQUEST_TYPE',
  defaultValue: '',
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

// The P-Loan save API used to be a separate service on its own host/port
// (`kPLoanSaveApiBase`, `:8082`) with an HTTP **Basic** credential baked into
// the bundle (`kPLoanSaveApiAuth`). Both were **deleted on 2026-08-04** when the
// endpoint moved to `POST <api_url_base>/ploan` — a mobile-API-style call that
// authenticates with the customer's own Firebase **bearer token** and needs no
// shipped credential. See `services/p_loan_contract_api.dart`. Removing the
// Basic secret from source closes the pentest finding it was flagged for.

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
    // The new UAT gateway requires it on every api_url_base call, same as prod
    // (was empty for the old uat host — changed 2026-08-04).
    srisawadHeader: 'x1',
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

  /// Value for the `x-srisawad` request header the mobile API expects, sent on
  /// every `api_url_base` call via [SrisawadApi.headers]. `x1` on both prod and
  /// the new uat gateway. Empty means "don't send the header" — no environment
  /// is empty today, but the mechanism is kept.
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
