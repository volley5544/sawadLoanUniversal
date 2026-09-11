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
    this.topupProductIcons = const {},
    String? ndidRequestType,
    String? topupProductIconDefault,
  })  : _ndidRequestType = ndidRequestType,
        _topupProductIconDefault = topupProductIconDefault;

  /// The whole `api_url` map, decoded. Kept raw so a newly-added key is usable
  /// without a code change (via [urlFor]).
  final Map<String, String> apiUrl;

  /// `sawad_loan_universal_version` — the newest web build the host expects in
  /// prod.
  final int? webVersionProd;

  /// `topup_product_icons` — SVG icon URL per add-on product code, for the
  /// **สิทธิพิเศษเฉพาะคุณ** tiles on the top-up contract card.
  ///
  /// A map keyed by product code, not the source project's two parallel
  /// arrays (`product_code` / `product_img`). Parallel arrays can desync, and
  /// in the source they effectively have: its generated record reads
  /// `produce_code` while the document stores `product_code`, so the lookup
  /// never matches and every tile falls back to the placeholder.
  ///
  /// The URLs are public Firebase Storage download links that answer
  /// `access-control-allow-origin: *`, so `flutter_svg` can fetch them from
  /// the browser.
  final Map<String, String> topupProductIcons;

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

  /// Base URL of the **NDID gateway** (`services/ndid_api.dart`).
  ///
  /// Config-driven for the same reason as [apiUrlBase]: the key is per-project,
  /// so the uat document points at the uat node and prod's at prod, and the
  /// gateway can be moved without a rebuild. Null falls back to [kNdidApiBase].
  ///
  /// ⚠ Inside the native host every NDID call goes through the `httpRequest`
  /// bridge, which only proxies **allowlisted URL prefixes**. Changing this
  /// value to a host the app doesn't allowlist breaks NDID in the app — see
  /// [NdidApi.baseUrl].
  String? get ndidUrlBase => urlFor('ndid_url_base');

  /// `request_type` for `POST /rp/verify`, if the document overrides it.
  ///
  /// Config-driven for the same reason as [ndidUrlBase], and it must move *with*
  /// it: each NDID gateway publishes its own valid set at `GET /request-types`
  /// and the sets don't overlap, so a gateway change without a matching request
  /// type earns `20091 - Invalid request type`. Null falls back to
  /// [kNdidRequestType].
  ///
  /// Read from the **top level** of the document, not the `api_url` map — it
  /// isn't a URL, and [urlFor] would strip a trailing character it shouldn't.
  /// `topup_product_icon_default` — shown for a product code the map has no
  /// entry for. Null leaves the tile with its built-in Material icon, which is
  /// still better than a broken image.
  String? get topupProductIconDefault {
    final raw = _topupProductIconDefault?.trim();
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  /// The icon for [productCode], falling back to the default and then to null.
  String? topupProductIcon(String productCode) {
    final url = topupProductIcons[productCode.trim()]?.trim();
    if (url != null && url.isNotEmpty) return url;
    return topupProductIconDefault;
  }

  String? get ndidRequestType {
    final raw = _ndidRequestType?.trim();
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  final String? _ndidRequestType;
  final String? _topupProductIconDefault;

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
      ndidRequestType: decoded['ndid_request_type']?.toString(),
      topupProductIcons: switch (decoded['topup_product_icons']) {
        final Map<String, dynamic> icons => {
            for (final entry in icons.entries)
              if (entry.value != null) entry.key: '${entry.value}',
          },
        _ => const {},
      },
      topupProductIconDefault:
          decoded['topup_product_icon_default']?.toString(),
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
