import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/services/auth_token.dart';
import 'package:sawad_loan_universal/services/native_bridge.dart';

/// The `?token=` launch param is an hour-lived credential that also does not
/// survive a reload (path URL strategy drops the query on the first
/// navigation), so the bearer is resolved from the host per request instead.
/// Everything here pins the same rule: **never end up with less credential
/// than the launch param already gave us.**
void main() {
  setUp(AuthToken.resetForTest);
  tearDown(AuthToken.resetForTest);

  group('pickToken', () {
    test('a host token wins over the launch param', () {
      expect(
        AuthToken.pickToken(fromHost: 'fresh-jwt', fallback: 'launch-jwt'),
        'fresh-jwt',
      );
    });

    test('null (old host, no such handler) falls back', () {
      expect(
        AuthToken.pickToken(fromHost: null, fallback: 'launch-jwt'),
        'launch-jwt',
      );
    });

    test('empty (host signed out) falls back rather than blanking', () {
      // Sending a token the backend rejects is better than sending none: the
      // 401 is what tells the app the session is gone, whereas an
      // unauthenticated call is indistinguishable from a coding mistake.
      expect(
        AuthToken.pickToken(fromHost: '', fallback: 'launch-jwt'),
        'launch-jwt',
      );
    });
  });

  group('resolve, off-host', () {
    test('no bridge at all: the launch param, and no call attempted', () async {
      // Under `flutter test` there is no window.flutter_inappwebview, and the
      // off-web stub throws — so the guard has to come first.
      expect(NativeCameraBridge.isSupported, isFalse);
      var calls = 0;
      AuthToken.fetcherOverride = () async {
        calls++;
        return 'fresh-jwt';
      };
      expect(await AuthToken.resolve('launch-jwt'), 'launch-jwt');
      expect(calls, 0);
    });
  });

  group('resolve, inside a host', () {
    setUp(() => AuthToken.supportedOverride = () => true);

    test('uses the host token', () async {
      AuthToken.fetcherOverride = () async => 'fresh-jwt';
      expect(await AuthToken.resolve('launch-jwt'), 'fresh-jwt');
    });

    test('an old host answering null falls back', () async {
      AuthToken.fetcherOverride = () async => null;
      expect(await AuthToken.resolve('launch-jwt'), 'launch-jwt');
    });

    test('a throwing bridge falls back instead of propagating', () async {
      AuthToken.fetcherOverride = () async => throw UnsupportedError('gone');
      expect(await AuthToken.resolve('launch-jwt'), 'launch-jwt');
    });

    test('a hanging host falls back once the timeout elapses', () async {
      // Nothing else bounds this: the host's currentFirebaseToken() has no
      // timeout and getIdToken() can block on the token endpoint. Without the
      // bound, every API call would wait behind a spinner forever.
      AuthToken.fetcherOverride = () => Future<String?>.delayed(
            AuthToken.kFetchTimeout * 3,
            () => 'too-late',
          );
      expect(
        await AuthToken.resolve('launch-jwt'),
        'launch-jwt',
      );
    }, timeout: Timeout(AuthToken.kFetchTimeout * 4));

    test('concurrent callers share one bridge hop', () async {
      // Two screens fire their customer + contract reads in parallel on
      // purpose; that should not be two round trips.
      var calls = 0;
      AuthToken.fetcherOverride = () async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return 'fresh-jwt';
      };
      final results = await Future.wait([
        AuthToken.resolve('launch-jwt'),
        AuthToken.resolve('launch-jwt'),
        AuthToken.resolve('launch-jwt'),
      ]);
      expect(results, ['fresh-jwt', 'fresh-jwt', 'fresh-jwt']);
      expect(calls, 1);
    });

    test('a later call fetches again rather than reusing the first', () async {
      // No caching by design — the host's token is already a cached read that
      // refreshes near expiry, so a second hop is cheap and always current.
      var calls = 0;
      AuthToken.fetcherOverride = () async {
        calls++;
        return 'fresh-jwt-$calls';
      };
      expect(await AuthToken.resolve('launch-jwt'), 'fresh-jwt-1');
      expect(await AuthToken.resolve('launch-jwt'), 'fresh-jwt-2');
    });
  });
}
