import 'dart:convert';

import '../config/app_environment.dart';
import '../models/app_config.dart';
import 'api_transport.dart';
import 'firebase_auth_rest.dart';
import 'firestore_rest.dart';

/// Reads the runtime-config document (`application/config` by default, see
/// [kAppConfigPath]) from Firestore over the **REST API** — the app carries no
/// Firebase SDK.
///
/// The result is memoised: [ensureLoaded] kicks the request off once and every
/// later caller awaits the same future, so API clients can `await` the config
/// without re-fetching and without blocking app boot.
///
/// **Security rules matter here.** Firestore rules are all-or-nothing per
/// document — a client that may read the document reads *every* field. The
/// default `application/config` also holds `agent_web_api_token` /
/// `agent_web_api_token_uat`, so granting client read on it publishes those
/// secrets. Point [kAppConfigPath] at a document holding only the public URL
/// map instead. Until a rule allows the read, [ensureLoaded] resolves to an
/// empty [AppConfig] and callers fall back to [AppEnvironment].
class AppConfigApi {
  AppConfigApi._();

  static Future<AppConfig>? _inFlight;
  static AppConfig? _loaded;

  /// The config if it has already resolved, else null. Non-blocking.
  static AppConfig? get cached => _loaded;

  /// Last failure reason, for logging/diagnostics. Null when the load succeeded
  /// or hasn't run.
  static String? lastError;

  /// Loads the config once and caches it. Never throws — on any failure it
  /// resolves to an empty [AppConfig] and records [lastError], because losing
  /// the config must degrade to the compile-time defaults, not break startup.
  static Future<AppConfig> ensureLoaded() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _fetch().then((config) {
      _loaded = config;
      return config;
    });
    _inFlight = future;
    return future;
  }

  /// Drops the cache so the next [ensureLoaded] re-fetches. For tests.
  static void reset() {
    _inFlight = null;
    _loaded = null;
    lastError = null;
  }

  static Future<AppConfig> _fetch() async {
    final segments = kAppConfigPath.split('/').where((s) => s.isNotEmpty);
    if (segments.length != 2) {
      lastError = 'APP_CONFIG_PATH must be "collection/document", '
          'got "$kAppConfigPath"';
      return const AppConfig();
    }
    final url = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/'
      '${AppEnvironment.current.firebaseProjectId}'
      '/databases/(default)/documents/'
      '${segments.map(Uri.encodeComponent).join('/')}',
    );

    // The rules require request.auth != null, satisfied by an anonymous
    // Firebase identity. `authToken` (the host's launch JWT) belongs to a
    // different Firebase project and is not accepted here.
    final idToken = await FirebaseAuthRest.idToken();
    if (idToken == null) {
      lastError = FirebaseAuthRest.lastError ?? 'no anonymous identity';
      return const AppConfig();
    }

    final ApiHttpResult res;
    try {
      res = await sendApiRequest(
        'GET',
        url,
        headers: {'Authorization': 'Bearer $idToken'},
        // Firestore's REST API is CORS-enabled (it allows the `authorization`
        // header on preflight) and is not on the host's bridge allowlist, so
        // going through the bridge made this read fail inside the app and the
        // config resolve empty — see sendApiRequest.
        bypassHostBridge: true,
      );
    } on ApiTransportException catch (e) {
      lastError = 'config unreachable: ${e.message}';
      return const AppConfig();
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      lastError = res.statusCode == 403
          ? 'config read denied (HTTP 403) — Firestore rules do not allow '
              'this identity to get $kAppConfigPath'
          : 'config read failed (HTTP ${res.statusCode})';
      return const AppConfig();
    }

    try {
      final json = jsonDecode(res.body);
      if (json is! Map<String, dynamic>) {
        lastError = 'config response was not an object';
        return const AppConfig();
      }
      final config = AppConfig.fromDecoded(decodeFirestoreFields(json['fields']));
      lastError = config.isEmpty ? 'config document has no api_url map' : null;
      return config;
    } catch (e) {
      lastError = 'config decode failed: $e';
      return const AppConfig();
    }
  }
}
