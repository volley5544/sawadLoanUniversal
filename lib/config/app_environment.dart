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
/// | `ndid.srisawadpower.com` (prod) | `dsign.accountopening`, `dsign.dcontract`, `easyconnext.lineoa`, `idpconnext.thaid` — read 2026-09-10; **no `dsign.dcontract.public`**, the one value uat has that prod does not |
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

/// Build-time override for the NDID `X-API-Key`. **Empty by default**, which
/// means "pick the key that goes with whichever gateway is resolved" — see
/// [ndidApiKeyFor]. Set it to pin one key regardless of gateway:
///
/// ```sh
/// flutter build web ... --dart-define=NDID_API_KEY=...
/// ```
const String kNdidApiKey = String.fromEnvironment('NDID_API_KEY');

/// `X-API-Key` for the **production** NDID gateway, `ndid.srisawadpower.com`.
const String _kNdidApiKeyProd = 'DV4zX7Ti0lkE0CcQcu0sGVmlSeqWUsAatYg2Uh6t';

/// `X-API-Key` for the two non-production nodes — `uat.ndid.srisawadpower.com`
/// and the `dev.swpfin.com/dap` SIT node, which share one key.
const String _kNdidApiKeyNonProd = 'ndid_Gl_dI1z8JCeHebNbnyzICvpCep3KHLYY1oeDHjfNTXI';

/// The `X-API-Key` for [base], the gateway `NdidApi.baseUrl()` resolved.
///
/// **Each gateway accepts only its own key** — verified 2026-09-10 against
/// `GET /request-types`: the prod key is 401 on uat, and the non-prod key is
/// 401 on prod. The two therefore have to move together.
///
/// They could not, until this existed. The gateway comes from
/// `api_url['ndid_url_base']` in the Firestore config, which changes with no
/// rebuild; the key is compiled in. So editing that one field — the whole
/// point of putting it in config — silently left the key behind, and every
/// NDID call 401'd until someone shipped a matching build. Keying off the
/// resolved host makes `ndid_url_base` sufficient on its own again, in both
/// directions, which is what makes a rollback a config edit rather than a
/// release.
///
/// Matched on host so a path-carrying base (`dev.swpfin.com/dap`) and any
/// trailing slash both land correctly; an unrecognised gateway gets the
/// non-prod key, since prod is the one whose key should never be guessed at.
///
/// Neither key is secret from anyone who opens the app — a web build ships
/// whatever it is built with. See the Security posture section of `CLAUDE.md`.
String ndidApiKeyFor(String base) {
  if (kNdidApiKey.isNotEmpty) return kNdidApiKey;
  final host = Uri.tryParse(base)?.host ?? '';
  return host == 'ndid.srisawadpower.com' ? _kNdidApiKeyProd : _kNdidApiKeyNonProd;
}

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

/// Base URL of the **lead** service the top-up flow falls back to when a
/// self-service top-up is not possible (`TopupOutcome.lead`): land/house loan
/// types, a `can_topup` refusal, or a payout above the contract's
/// `max_transfer_amount`. The path appended to it is
/// `/ssw_service_api/api/leads/lh-save`.
///
/// Reachable from `api_url['lead_url_base']` in the Firestore runtime config
/// too — see `TopupApi.leadBaseUrl`. Config first, this define as the
/// degrade-to value, the same rule every other endpoint here follows.
const String kTopupLeadApiBase = String.fromEnvironment('TOPUP_LEAD_API_BASE');

/// Credentials for that lead service.
///
/// ⚠ **Empty by default, and that is deliberate.** The FlutterFlow source
/// hardcoded both an `x-api-key` and a Basic-style bearer into the bundle.
/// Reintroducing them here would put a shared service credential back into a
/// web build that anyone can read — exactly the finding that closing
/// `kPLoanSaveApiAuth` resolved on 2026-08-04. So they are build-time inputs
/// with no shipped value: unset, the lead branch reports itself unconfigured
/// rather than calling the endpoint unauthenticated.
///
/// ```sh
/// flutter build web ... --dart-define=TOPUP_LEAD_API_KEY=... \
///                       --dart-define=TOPUP_LEAD_API_AUTH=...
/// ```
///
/// The real fix is for this call to move behind the mobile API and
/// authenticate with the customer's own bearer token, like `POST /ploan` does.
const String kTopupLeadApiKey = String.fromEnvironment('TOPUP_LEAD_API_KEY');
const String kTopupLeadApiAuth = String.fromEnvironment('TOPUP_LEAD_API_AUTH');

/// Whether the lead fallback is configured well enough to call.
bool get kTopupLeadApiConfigured =>
    kTopupLeadApiKey.isNotEmpty && kTopupLeadApiAuth.isNotEmpty;

/// Pins `as_id_list` on `POST /rp/verify-with-data` to one Authoritative
/// Source node id, instead of resolving it from the chosen IdP.
///
/// ⚠ **A last resort, and environment-scoped.** The normal path is
/// `NdidApi.findAsForIdp`, which matches the IdP's `(industry_code,
/// company_code)` against the AS list — that asks the same institution the
/// customer consented to, and needs no gateway-specific id. A node id
/// compiled into the client is the `'Authen Only'` `request_type` mistake of
/// 2026-07-31 in a new costume: it works on the gateway it came from and fails
/// on every other one.
///
/// So this exists only for a gateway whose AS list cannot be resolved — uat as
/// of 2026-09-11 — and the **config document is the place to set it**
/// (`ndid_as_id` / `ndid_as_id_uat`), so it stays per-environment and can be
/// removed without a rebuild. This define is only the degrade-to, and ships
/// empty.
const String kNdidAsId = String.fromEnvironment('NDID_AS_ID');

/// Marketing name for [kNdidAsId], for the Request Message's AS clause.
///
/// Optional: when it is unset the client tries to resolve the name from the
/// gateway's own AS list, and if that fails it **omits the clause** rather
/// than naming a source it cannot confirm.
const String kNdidAsName = String.fromEnvironment('NDID_AS_NAME');

/// Base URL of **`POST /GetRecalTopupData`** — the recalculation behind the
/// top-up amount screen's ยอดที่ต้องชำระเพื่อเติมวงเงิน block.
///
/// ⚠ **Not reachable from a browser as supplied** (verified 2026-09-12). The
/// sample points at `http://34.142.213.42:8080`, which fails twice over from
/// this HTTPS build:
///
///   1. **Plain HTTP on an IP** — blocked as mixed content before it is sent.
///   2. **No CORS.** A `200` carries no `access-control-allow-*` header, and
///      the `OPTIONS` preflight answers `401` because a browser never sends
///      `Authorization` on a preflight. Exactly what made the retired
///      `<:8082>/SavePloanContract` need the native bridge.
///
/// So the call only works **inside the host**, through its `httpRequest`
/// bridge — and only once `http://34.142.213.42:8080/` is added to
/// `_kHttpRequestAllowedPrefixes` in the srisawad app, which costs an app
/// release. Until then the amount screen simply shows no settlement block
/// (see [kTopupRecalApiAuth]).
///
/// Resolving from the runtime config first (`api_url['recal_topup_url_base']`)
/// is what lets the endpoint be moved behind the mobile API base — HTTPS,
/// `access-control-allow-origin: *`, bearer auth — without a rebuild. That is
/// the fix worth asking for.
const String kTopupRecalApiBase = String.fromEnvironment(
  'TOPUP_RECAL_API_BASE',
  defaultValue: 'http://34.142.213.42:8080',
);

/// The `Authorization` header value for [kTopupRecalApiBase], e.g.
/// `Basic <base64>`.
///
/// ⚠ **Empty by default, and it must stay that way.** The supplied curl
/// carries a **shared service account** (`Basic …`, a `…prod` user), and
/// baking one into a web bundle is the high-severity pentest finding this repo
/// closed on 2026-08-04 by deleting `kPLoanSaveApiAuth` — anyone who opens the
/// app can read it. Same rule as [kTopupLeadApiAuth].
///
/// Unset, [kTopupRecalConfigured] is false, no call is made, and the
/// ยอดที่ต้องชำระเพื่อเติมวงเงิน section is **hidden** — which is the same
/// thing an empty `settlement_items` does, so the screen has one behaviour
/// rather than two. `test/topup_recalculation_test.dart` pins that nothing
/// ships.
///
/// The real fix is for this call to move behind the mobile API and
/// authenticate with the customer's own bearer token, the way `POST /ploan`
/// does — see Outstanding #33.
const String kTopupRecalApiAuth = String.fromEnvironment('TOPUP_RECAL_API_AUTH');

/// Whether a build can call `POST /GetRecalTopupData` at all.
bool get kTopupRecalConfigured => kTopupRecalApiAuth.isNotEmpty;

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
    pdfLoanSrisawadHeader: 'x1_c3Jpc2F3YWQ',
  ),
  uat(
    name: 'uat',
    firebaseProjectAlias: 'uat',
    firebaseProjectId: 'sawad-loan-universal-uat',
    firebaseApiKey: 'AIzaSyDty7ZRY-LS1K31L8w2inZsRyE7wOccFEI',
    // Matches `api_url.api_url_base` in the uat config document. Changed
    // 2026-09-11 from `https://dev.swpfin.com:7076`, which **no longer
    // serves** — that host had been the fallback for most of this project's
    // life, and leaving it here meant any failure to read the config (denied
    // rule, failed anonymous sign-in, Firestore unreachable) degraded the app
    // onto a dead gateway instead of a working one. A fallback is only worth
    // having if it works.
    mobileApiBase: 'https://srisawad-qa.ecorpgroup.com',
    // The new UAT gateway requires it on every api_url_base call, same as prod
    // (was empty for the old uat host — changed 2026-08-04).
    srisawadHeader: 'x1',
    // The uat gateway wants the ordinary value here too — only prod still
    // expects the special one (changed 2026-08-07).
    pdfLoanSrisawadHeader: 'x1',
  );

  const AppEnvironment({
    required this.name,
    required this.firebaseProjectAlias,
    required this.firebaseProjectId,
    required this.firebaseApiKey,
    required this.mobileApiBase,
    required this.srisawadHeader,
    required this.pdfLoanSrisawadHeader,
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

  /// `x-srisawad` for **`POST /pdf/loan` only**, which is the one endpoint on
  /// this base that doesn't take [srisawadHeader].
  ///
  /// | Env | Value |
  /// | --- | --- |
  /// | prod | `x1_c3Jpc2F3YWQ` |
  /// | uat | `x1` — same as every other call (changed 2026-08-07) |
  ///
  /// It is per-environment rather than the one constant it used to be because
  /// the two gateways disagree: uat wants the ordinary value and prod still
  /// wants the special one. Sending the wrong one is not a silent difference —
  /// the gateway refuses the request, so the contract PDFs never generate and
  /// step 6 cannot reach its submit gate.
  final String pdfLoanSrisawadHeader;

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
