import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/config/app_environment.dart';

/// Each NDID gateway accepts only its own `X-API-Key` — verified 2026-09-10
/// against `GET /request-types`, where the prod key is 401 on uat and the
/// non-prod key is 401 on prod. The gateway is picked at runtime from the
/// Firestore config (`api_url.ndid_url_base`) while the key is compiled in, so
/// nothing but this pairing keeps the two in step when that field is edited.
void main() {
  const prodKey = 'DV4zX7Ti0lkE0CcQcu0sGVmlSeqWUsAatYg2Uh6t';
  const nonProdKey = 'ndid_Gl_dI1z8JCeHebNbnyzICvpCep3KHLYY1oeDHjfNTXI';

  group('ndidApiKeyFor pairs the key with the gateway', () {
    test('the prod gateway gets the prod key', () {
      expect(ndidApiKeyFor('https://ndid.srisawadpower.com'), prodKey);
    });

    test('a trailing slash does not change the host match', () {
      expect(ndidApiKeyFor('https://ndid.srisawadpower.com/'), prodKey);
    });

    test('uat is a different host, not a prefix of prod, and keeps its own key', () {
      expect(ndidApiKeyFor('https://uat.ndid.srisawadpower.com'), nonProdKey);
    });

    test('the SIT node carries a path, which must not defeat the match', () {
      expect(ndidApiKeyFor('https://dev.swpfin.com/dap'), nonProdKey);
    });

    test('the two keys are distinct, or the pairing asserts nothing', () {
      expect(prodKey, isNot(nonProdKey));
    });

    test('an unrecognised gateway does not fall through to the prod key', () {
      expect(ndidApiKeyFor('https://example.invalid'), nonProdKey);
      expect(ndidApiKeyFor(''), nonProdKey);
      expect(ndidApiKeyFor('not a url'), nonProdKey);
    });

    test('a lookalike host does not borrow the prod key', () {
      // Host equality, not a substring test: these all contain the prod host
      // as a suffix or fragment but are not it.
      expect(ndidApiKeyFor('https://evil-ndid.srisawadpower.com'), nonProdKey);
      expect(ndidApiKeyFor('https://ndid.srisawadpower.com.evil.test'), nonProdKey);
    });

    test('no build-time override is set, so the pairing is what ships', () {
      // If this fails someone passed --dart-define=NDID_API_KEY, which pins one
      // key for every gateway and silently disables the pairing above.
      expect(kNdidApiKey, isEmpty);
    });
  });
}
