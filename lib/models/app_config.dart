/// Runtime configuration read from the Firestore document `application/config`
/// at startup — the same document the srisawad mobile app reads, so both share
/// one source of truth for API endpoints.
///
/// Everything here is optional. When the document can't be read the app falls
/// back to the compile-time values on [AppEnvironment], so a config outage
/// degrades rather than breaks. See `services/app_config_api.dart`.
library;

import '../config/app_environment.dart';

/// The `api_url` map plus the top-level keys this app cares about.
class AppConfig {
  const AppConfig({
    this.apiUrl = const {},
    this.webVersionProd,
    this.webVersionUat,
    this.topupProductIcons = const {},
    this.topupProductIconsUat = const {},
    String? ndidRequestType,
    String? ndidRequestTypeUat,
    String? topupProductIconDefault,
    String? topupProductIconDefaultUat,
  })  : _ndidRequestType = ndidRequestType,
        _ndidRequestTypeUat = ndidRequestTypeUat,
        _topupProductIconDefault = topupProductIconDefault,
        _topupProductIconDefaultUat = topupProductIconDefaultUat;

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
  /// ⚠ **No longer the preferred key** (changed 2026-09-11). It names no
  /// environment, so a document serving both would hand uat the prod host.
  /// `SrisawadApi.baseUrl` reads [apiUrlForEnvironment] first and treats this
  /// as the fallback for a document carrying neither of the pair.
  String? get apiUrlBase => urlFor('api_url_base');

  /// The per-environment mobile-API endpoints — **the authoritative pair**.
  ///
  /// These keep their original `_prod`/`_dev` spelling rather than moving to
  /// the `_uat` suffix: they already exist under these names in both
  /// documents, and renaming a live key to tidy a convention is how an
  /// environment ends up on the wrong gateway.
  String? get apiUrlProd => urlFor('api_url_prod');
  String? get apiUrlDev => urlFor('api_url_dev');

  /// [apiUrlProd] on a prod build, [apiUrlDev] on a uat one.
  String? get apiUrlForEnvironment =>
      AppEnvironment.current.isProd ? apiUrlProd : apiUrlDev;

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
    if (!AppEnvironment.current.isProd) {
      final uat = _topupProductIconDefaultUat?.trim();
      if (uat != null && uat.isNotEmpty) return uat;
    }
    final raw = _topupProductIconDefault?.trim();
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  /// Per-environment override of [topupProductIcons], from
  /// `topup_product_icons_uat`.
  final Map<String, String> topupProductIconsUat;

  /// The icon map for the active environment — the `_uat` one on a uat build
  /// when it has entries, else the bare one.
  Map<String, String> get topupProductIconsForEnvironment =>
      (!AppEnvironment.current.isProd && topupProductIconsUat.isNotEmpty)
          ? topupProductIconsUat
          : topupProductIcons;

  /// The icon for [productCode], falling back to the default and then to null.
  String? topupProductIcon(String productCode) {
    final url = topupProductIconsForEnvironment[productCode.trim()]?.trim();
    if (url != null && url.isNotEmpty) return url;
    return topupProductIconDefault;
  }

  String? get ndidRequestType {
    if (!AppEnvironment.current.isProd) {
      final uat = _ndidRequestTypeUat?.trim();
      if (uat != null && uat.isNotEmpty) return uat;
    }
    final raw = _ndidRequestType?.trim();
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  final String? _ndidRequestType;
  final String? _ndidRequestTypeUat;
  final String? _topupProductIconDefault;
  final String? _topupProductIconDefaultUat;

  /// The value of [key] **for the active environment**.
  ///
  /// uat reads `<key>_uat` and prod reads the bare `<key>`, matching the
  /// `sawad_loan_universal_version` / `…_version_uat` pair the host app
  /// already uses. Environments are separated by **field name**, not only by
  /// living in different Firebase projects — so one document can serve both,
  /// and a key set for one environment cannot leak into the other.
  ///
  /// ⚠ uat falls back to the bare key when no `_uat` variant exists. That
  /// keeps a document predating this convention working and lets the `_uat`
  /// keys be added one at a time. It does mean a *shared* document carrying
  /// only bare keys would give uat the prod value — safe here because the two
  /// environments are also separate projects, but it is the thing to check if
  /// a uat build ever reads a prod endpoint.
  String? envValue(Map<String, String> source, String key) {
    if (!AppEnvironment.current.isProd) {
      final uat = source['${key}_uat']?.trim();
      if (uat != null && uat.isNotEmpty) return uat;
    }
    return source[key]?.trim();
  }

  /// Any `api_url` entry, trimmed and with a trailing slash removed so callers
  /// can append `/loan/list` without producing a double slash. Returns null
  /// when absent or blank.
  String? urlFor(String key) {
    final raw = envValue(apiUrl, key);
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
      ndidRequestTypeUat: decoded['ndid_request_type_uat']?.toString(),
      topupProductIcons: _asStringMap(decoded['topup_product_icons']),
      topupProductIconsUat: _asStringMap(decoded['topup_product_icons_uat']),
      topupProductIconDefault:
          decoded['topup_product_icon_default']?.toString(),
      topupProductIconDefaultUat:
          decoded['topup_product_icon_default_uat']?.toString(),
    );
  }

  static Map<String, String> _asStringMap(dynamic value) => switch (value) {
        final Map<String, dynamic> map => {
            for (final entry in map.entries)
              if (entry.value != null) entry.key: '${entry.value}',
          },
        _ => const {},
      };

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}');
  }

  @override
  String toString() =>
      'AppConfig(${apiUrl.length} api_url keys, uatVersion=$webVersionUat)';
}
