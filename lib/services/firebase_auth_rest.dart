import 'dart:convert';

import '../config/app_environment.dart';
import 'api_transport.dart';

/// Minimal anonymous Firebase Auth client, over the Identity Toolkit REST API.
///
/// The app carries **no Firebase SDK** (see CLAUDE.md), so this is the whole
/// integration: one `accounts:signUp` call that returns an ID token, used as
/// the `Authorization: Bearer` on the Firestore config read.
///
/// ## Why anonymous auth at all
///
/// The Firestore rules gate the public config document on
/// `request.auth != null`. That is **not** an access control — anyone can mint
/// an anonymous token with the public web API key, which ships in this bundle.
/// What it buys is:
///
///   - every read is attributable to a Firebase UID, so abuse is traceable and
///     rate-limitable per identity rather than per IP;
///   - the rules never have to say `if true`, so a future document added under
///     an authenticated match block doesn't silently become world-readable;
///   - it is the hook App Check plugs into when real bot protection is wanted.
///
/// The **actual** protection is that the client-readable document contains no
/// secrets: `application/config` (which holds the `agent_web_api_token*`
/// values) is not reachable by any client rule.
///
/// The API key is not a credential. It identifies the project to Google's
/// endpoints and is expected to be public in a web client; it grants nothing on
/// its own.
class FirebaseAuthRest {
  FirebaseAuthRest._();

  static const String _signUpUrl =
      'https://identitytoolkit.googleapis.com/v1/accounts:signUp';

  /// Refresh a little before the hour is up, so a long-lived session doesn't
  /// make a request with a token that expires in flight.
  static const Duration _renewMargin = Duration(minutes: 5);

  static String? _idToken;
  static DateTime? _expiresAt;
  static Future<String?>? _inFlight;

  /// Last failure reason, for diagnostics. Null when signed in or unattempted.
  static String? lastError;

  /// The signed-in UID, when there is one.
  static String? uid;

  /// An anonymous ID token, or null when sign-in isn't possible.
  ///
  /// Never throws — the caller falls back to compile-time config, so an auth
  /// outage must degrade rather than break startup. Concurrent callers share
  /// one request, and a cached token is reused until it nears expiry.
  static Future<String?> idToken() {
    final cached = _idToken;
    final expiry = _expiresAt;
    if (cached != null &&
        expiry != null &&
        DateTime.now().isBefore(expiry.subtract(_renewMargin))) {
      return Future.value(cached);
    }
    return _inFlight ??= _signIn().whenComplete(() => _inFlight = null);
  }

  /// Drops the cached identity. For tests.
  static void reset() {
    _idToken = null;
    _expiresAt = null;
    _inFlight = null;
    lastError = null;
    uid = null;
  }

  static Future<String?> _signIn() async {
    final key = AppEnvironment.current.firebaseApiKey;
    if (key.isEmpty) {
      lastError = 'no firebaseApiKey configured for '
          '${AppEnvironment.current.name}';
      return null;
    }

    final ApiHttpResult res;
    try {
      res = await sendApiRequest(
        'POST',
        Uri.parse('$_signUpUrl?key=$key'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'returnSecureToken': true}),
      );
    } on ApiTransportException catch (e) {
      lastError = 'anonymous sign-in unreachable: ${e.message}';
      return null;
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      // The usual cause is anonymous sign-in being disabled for the project
      // (Authentication → Sign-in method → Anonymous).
      lastError = 'anonymous sign-in failed (HTTP ${res.statusCode})';
      return null;
    }

    try {
      final json = jsonDecode(res.body);
      if (json is! Map<String, dynamic>) {
        lastError = 'anonymous sign-in returned an unexpected body';
        return null;
      }
      final token = '${json['idToken'] ?? ''}';
      if (token.isEmpty) {
        lastError = 'anonymous sign-in returned no idToken';
        return null;
      }
      final seconds = int.tryParse('${json['expiresIn'] ?? ''}') ?? 3600;
      _idToken = token;
      _expiresAt = DateTime.now().add(Duration(seconds: seconds));
      uid = '${json['localId'] ?? ''}';
      lastError = null;
      return token;
    } catch (e) {
      lastError = 'anonymous sign-in decode failed: $e';
      return null;
    }
  }
}
