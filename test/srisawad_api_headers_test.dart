import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/config/app_environment.dart';
import 'package:sawad_loan_universal/services/srisawad_api.dart';

/// `SrisawadApi.headers` is the single place every `api_url_base` call gets its
/// credentials from — `TopupApi`, `PLoanApi`, `UserApi` and `PLoanContractApi`
/// all route through it. Nothing covered it until now, which is how
/// `GET /user/detail` came to be called with no bearer at all: the header
/// builder was right and one caller simply never passed a token (pentest
/// finding #2).
///
/// These pin the contract itself. The compiler pins the callers — `token` is a
/// required argument on every one of them.
void main() {
  group('mobile-API headers', () {
    test('carry the bearer token and x-srisawad', () {
      final h = SrisawadApi.headers('jwt-abc');
      expect(h['Authorization'], 'Bearer jwt-abc');
      expect(h['x-srisawad'], AppEnvironment.current.srisawadHeader);
    });

    test('omit Authorization entirely when there is no token', () {
      // Not `Bearer ` with nothing after it: an empty credential reads as
      // authenticated in a capture while granting nothing. Absent is honest.
      final h = SrisawadApi.headers('');
      expect(h.containsKey('Authorization'), isFalse);
      expect(h.values, isNot(contains('Bearer ')));
    });

    test('Content-Type is set only for a body-carrying request', () {
      expect(SrisawadApi.headers('jwt').containsKey('Content-Type'), isFalse);
      expect(
        SrisawadApi.headers('jwt', contentType: 'application/json')['Content-Type'],
        'application/json',
      );
    });

    test('extra headers merge, and can override the per-call x-srisawad', () {
      // /pdf/loan is the one endpoint on this base with its own x-srisawad
      // value, and it supplies it this way.
      final h = SrisawadApi.headers('jwt', extra: {'x-srisawad': 'x1_other'});
      expect(h['x-srisawad'], 'x1_other');
      expect(h['Authorization'], 'Bearer jwt');
    });
  });
}
