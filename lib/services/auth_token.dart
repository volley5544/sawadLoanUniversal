import 'package:flutter/foundation.dart' show visibleForTesting;

import 'native_bridge.dart';

/// Resolves the customer's Firebase bearer token, asking the native host first.
///
/// ## Why the launch param is not enough
///
/// The host launches this build with the token in the URL (`?token=`), read
/// once in `main.dart` into `AppState.authToken`. Two things break that as a
/// session-long credential:
///
///   * Firebase ID tokens expire after an hour, and a P-Loan application
///     routinely takes longer — the tail of a long flow used to 401, including
///     the `/ploan` submit at the very end.
///   * Path URL strategy is on, so go_router replaces the whole location on
///     navigation and the launch query is gone after step 1. Every reload
///     (the host's stale-build reload, the iOS content-process reload, its
///     manual retry button) then re-boots this app with **no** token.
///
/// So the token is resolved per request from the host's `getAuthToken` handler,
/// which answers from the Firebase SDK. `AppState.authToken` remains only as
/// the fallback, for a plain browser and for a host too old to have the
/// handler.
///
/// No caching: the host's `getIdToken()` is itself a cached read that refreshes
/// near expiry, and the app force-refreshes every 60 s while its home page is
/// mounted, so a bridge hop always yields a token minted seconds ago. A local
/// cache here would only add an expiry heuristic that can be wrong.
abstract final class AuthToken {
  /// Bounds one bridge round-trip. Nothing else does: the host's
  /// `currentFirebaseToken()` has no timeout of its own and `getIdToken()` can
  /// block on `securetoken.googleapis.com`, so without this a cold or
  /// near-expiry refresh on a bad network would hang every API call behind a
  /// spinner with no error. On timeout we fall back rather than fail.
  static const Duration kFetchTimeout = Duration(seconds: 10);

  /// Set in tests to stand in for the host handler.
  @visibleForTesting
  static Future<String?> Function()? fetcherOverride;

  /// Set in tests to pretend a host is (or isn't) present.
  @visibleForTesting
  static bool Function()? supportedOverride;

  /// Shared across callers that ask at the same moment.
  static Future<String>? _inFlight;

  @visibleForTesting
  static void resetForTest() {
    fetcherOverride = null;
    supportedOverride = null;
    _inFlight = null;
  }

  /// Which token to use. Pure, so the choice is testable without a host.
  ///
  /// An empty [fromHost] means the host has nobody signed in; it still falls
  /// back, because dropping to an unauthenticated call is worse than sending a
  /// token the backend can reject — the 401 is what tells the app the session
  /// is gone.
  @visibleForTesting
  static String pickToken({required String? fromHost, required String fallback}) =>
      (fromHost == null || fromHost.isEmpty) ? fallback : fromHost;

  /// The bearer to send, host-first, with [launchToken] as the fallback.
  ///
  /// Never throws and never returns empty when [launchToken] is non-empty: a
  /// bridge failure must degrade to the launch token, not break the call.
  static Future<String> resolve(String launchToken) {
    final supported = supportedOverride?.call() ?? NativeCameraBridge.isSupported;
    if (!supported) return Future<String>.value(launchToken); // plain browser

    // Two screens deliberately fire their customer + contract reads in
    // parallel; share one hop rather than making two.
    final pending = _inFlight;
    if (pending != null) return pending;

    final fetch = _fetch(launchToken);
    _inFlight = fetch;
    return fetch;
  }

  static Future<String> _fetch(String launchToken) async {
    try {
      final fetcher = fetcherOverride ?? NativeCameraBridge.fetchAuthToken;
      final fromHost = await fetcher().timeout(kFetchTimeout);
      return pickToken(fromHost: fromHost, fallback: launchToken);
    } catch (_) {
      // Timeout, an old host that throws, a bridge that went away mid-call.
      return launchToken;
    } finally {
      _inFlight = null;
    }
  }
}
