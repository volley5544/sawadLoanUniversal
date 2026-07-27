/// Runtime configuration read from the Firestore document `application/config`
/// at startup — the same document the srisawad mobile app reads, so both share
/// one source of truth for API endpoints.
///
/// Everything here is optional. When the document can't be read the app falls
/// back to the compile-time values on [AppEnvironment], so a config outage
/// degrades rather than breaks. See `services/app_config_api.dart`.
library;

/// The `api_url` map plus the top-level keys this app cares about.
class AppConfig {
  const AppConfig({
    this.apiUrl = const {},
    this.webVersionProd,
    this.webVersionUat,
  });

  /// The whole `api_url` map, decoded. Kept raw so a newly-added key is usable
  /// without a code change (via [urlFor]).
  final Map<String, String> apiUrl;

  /// `sawad_loan_universal_version` — the newest web build the host expects in
  /// prod.
  final int? webVersionProd;

  /// `sawad_loan_universal_version_uat` — same, for uat.
  final int? webVersionUat;

  /// Mobile-API base for the P-Loan / top-up calls.
  ///
  /// `api_url_base` is the per-project base: in the uat Firebase project it
  /// holds the uat host, in prod it holds the prod host. That is why it is
  /// preferred over the explicit `api_url_prod` / `api_url_dev` pair — those
  /// are absolute and would cross environments.
  String? get apiUrlBase => urlFor('api_url_base');

  /// Explicit per-environment endpoints, used only as fallbacks.
  String? get apiUrlProd => urlFor('api_url_prod');
  String? get apiUrlDev => urlFor('api_url_dev');

  /// Any `api_url` entry, trimmed and with a trailing slash removed so callers
  /// can append `/loan/list` without producing a double slash. Returns null
  /// when absent or blank.
  String? urlFor(String key) {
    final raw = apiUrl[key]?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  bool get isEmpty => apiUrl.isEmpty;

  /// Builds from a decoded Firestore document (see
  /// `services/firestore_rest.dart`). Tolerant of missing/oddly-typed fields.
  factory AppConfig.fromDecoded(Map<String, dynamic> decoded) {
    final rawUrls = decoded['api_url'];
    return AppConfig(
      apiUrl: rawUrls is Map<String, dynamic>
          ? {
              for (final entry in rawUrls.entries)
                if (entry.value != null) entry.key: '${entry.value}',
            }
          : const {},
      webVersionProd: _asInt(decoded['sawad_loan_universal_version']),
      webVersionUat: _asInt(decoded['sawad_loan_universal_version_uat']),
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}');
  }

  @override
  String toString() =>
      'AppConfig(${apiUrl.length} api_url keys, uatVersion=$webVersionUat)';
}
