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

  /// The `/loan/list` body kept for the loan detail screen's response dialog.
  /// The dialog is copyable, so what `report` contains is a security property,
  /// not a formatting preference.
  group('RawApiExchange', () {
    const exchange = RawApiExchange(
      method: 'GET',
      url: 'https://api/loan/list?hash_thai_id=7693c1abc',
      statusCode: 200,
      body: '{"results":[{"contract_no":"C-1"}]}',
    );

    test('re-indents a JSON body without changing it', () {
      expect(exchange.prettyBody, contains('"contract_no": "C-1"'));
      expect(exchange.prettyBody, contains('\n'), reason: 'indented');
    });

    test('shows a non-JSON body as sent', () {
      // An HTML 500 page is exactly when the body matters most; swallowing it
      // because it will not parse would throw away the answer.
      const html = RawApiExchange(
        method: 'GET',
        url: 'https://api/loan/list',
        statusCode: 500,
        body: '<html>Internal Server Error</html>',
      );
      expect(html.prettyBody, '<html>Internal Server Error</html>');
    });

    test('report masks the customer hash and keeps the status', () {
      expect(exchange.report, isNot(contains('7693c1abc')));
      expect(exchange.report, startsWith('GET https://api/loan/list?'));
      expect(exchange.report, contains('HTTP 200'));
      expect(exchange.report, contains('"contract_no": "C-1"'));
    });
  });
}
