import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/models/app_config.dart';
import 'package:sawad_loan_universal/services/firestore_rest.dart';

/// A trimmed-down copy of the real `application/config` document as the
/// Firestore REST API returns it.
const _document = <String, dynamic>{
  'name': 'projects/sawad-loan-universal-uat/databases/(default)/documents/'
      'application/config',
  'fields': {
    'api_url': {
      'mapValue': {
        'fields': {
          'api_url_base': {'stringValue': 'https://dev.swpfin.com:7076'},
          'api_url_prod': {'stringValue': 'https://mobile-api.swpfin.com'},
          'api_url_dev': {'stringValue': 'https://dev.swpfin.com:7076'},
          'ndid_url_base': {
            'stringValue': 'https://uat.ndid.srisawadpower.com',
          },
          'mgm_user_manual_url': {'stringValue': ''},
        },
      },
    },
    'sawad_loan_universal_version': {'integerValue': '1'},
    'sawad_loan_universal_version_uat': {'integerValue': '25'},
    'topup_text_list': {
      'arrayValue': {
        'values': [
          {'stringValue': '• จ่ายตรง'},
          {'stringValue': '• จ่ายช้า'},
        ],
      },
    },
  },
};

void main() {
  group('Firestore REST decoding', () {
    test('unwraps strings, ints, maps and arrays', () {
      final decoded = decodeFirestoreFields(_document['fields']);

      expect(decoded['sawad_loan_universal_version_uat'], 25);
      expect(decoded['sawad_loan_universal_version'], 1);
      expect(decoded['api_url'], isA<Map<String, dynamic>>());
      expect((decoded['api_url'] as Map)['api_url_base'],
          'https://dev.swpfin.com:7076');
      expect(decoded['topup_text_list'], ['• จ่ายตรง', '• จ่ายช้า']);
    });

    test('integerValue arrives as a string on the wire', () {
      expect(decodeFirestoreValue(const {'integerValue': '42'}), 42);
      expect(decodeFirestoreValue(const {'integerValue': 42}), 42);
    });

    test('unhandled value types decode to null rather than throwing', () {
      // A geoPoint would take the app down at startup if this threw.
      expect(
        decodeFirestoreValue(const {
          'geoPointValue': {'latitude': 13.7, 'longitude': 100.5},
        }),
        isNull,
      );
      expect(decodeFirestoreValue('not a value'), isNull);
      expect(decodeFirestoreFields(null), isEmpty);
    });

    test('nullValue and missing fields are tolerated', () {
      expect(decodeFirestoreValue(const {'nullValue': null}), isNull);
      expect(decodeFirestoreFields(const {}), isEmpty);
    });
  });

  group('AppConfig', () {
    test('reads api_url_base and the version stamps', () {
      final config =
          AppConfig.fromDecoded(decodeFirestoreFields(_document['fields']));

      expect(config.apiUrlBase, 'https://dev.swpfin.com:7076');
      expect(config.apiUrlProd, 'https://mobile-api.swpfin.com');
      expect(config.webVersionUat, 25);
      expect(config.webVersionProd, 1);
      expect(config.isEmpty, isFalse);
    });

    test('strips a trailing slash so paths do not double up', () {
      // The original dump had 'https://mobile-api.swpfin.com/'; appending
      // '/loan/list' to that would produce a '//' path.
      final config = AppConfig(
        apiUrl: const {'api_url_base': 'https://mobile-api.swpfin.com/'},
      );
      expect(config.apiUrlBase, 'https://mobile-api.swpfin.com');
    });

    test('blank and missing keys read as null, not empty string', () {
      final config =
          AppConfig.fromDecoded(decodeFirestoreFields(_document['fields']));
      // mgm_user_manual_url is present but empty in the real document.
      expect(config.urlFor('mgm_user_manual_url'), isNull);
      expect(config.urlFor('nope'), isNull);
    });

    test('an unreadable document yields an empty config, not a crash', () {
      const config = AppConfig();
      expect(config.isEmpty, isTrue);
      expect(config.apiUrlBase, isNull);
      // Callers fall back to AppEnvironment when this is null.
    });

    test('any api_url key is reachable without a code change', () {
      final config =
          AppConfig.fromDecoded(decodeFirestoreFields(_document['fields']));
      expect(config.urlFor('api_url_dev'), 'https://dev.swpfin.com:7076');
    });
  });

  group('NDID gateway base URL', () {
    test('reads ndid_url_base out of the api_url map', () {
      final config =
          AppConfig.fromDecoded(decodeFirestoreFields(_document['fields']));

      // The key name is the contract with the Firestore document — a typo here
      // silently falls back to the compile-time gateway instead of failing.
      expect(config.ndidUrlBase, 'https://uat.ndid.srisawadpower.com');
    });

    test('trailing slash is stripped so /idp/list does not double up', () {
      final config = AppConfig(
        apiUrl: const {'ndid_url_base': 'https://uat.ndid.srisawadpower.com/'},
      );
      expect(config.ndidUrlBase, 'https://uat.ndid.srisawadpower.com');
    });

    test('absent or blank falls through to the compile-time default', () {
      // NdidApi.baseUrl() resolves `ndidUrlBase ?? kNdidApiBase`, so null here
      // is what keeps NDID working when the config document is unreadable.
      expect(const AppConfig().ndidUrlBase, isNull);
      expect(
        AppConfig(apiUrl: const {'ndid_url_base': '  '}).ndidUrlBase,
        isNull,
      );
    });
  });
}
