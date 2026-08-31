import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/services/ndid_api.dart';
import 'package:sawad_loan_universal/services/ndid_common_message.dart';

/// One `id_providers` entry exactly as the uat gateway returns it, including
/// `logo_url` / `has_logo` — the fields the bank grid draws its tiles from.
const _idpJson = <String, dynamic>{
  'id': '0DEC58C5-EE44-48CD-BD0A-B4C513C28E6D',
  'display_name': 'Mock Auto 1',
  'display_name_th': 'ทดสอบ อัตโนมัติ 1',
  'agent': false,
  'on_the_fly_support': true,
  'industry_code': '019',
  'company_code': '001',
  'marketing_name_en': 'Mock Auto 1',
  'marketing_name_th': 'ทดสอบ อัตโนมัติ 1',
  'logo_url': 'https://uat.ndid.srisawadpower.com/idp-logos/_default.svg',
  'has_logo': false,
};

void main() {
  group('NdidIdp', () {
    test('parses the logo fields the bank tiles need', () {
      final idp = NdidIdp.fromJson(_idpJson);

      expect(idp.id, '0DEC58C5-EE44-48CD-BD0A-B4C513C28E6D');
      expect(idp.displayNameTh, 'ทดสอบ อัตโนมัติ 1');
      expect(idp.logoUrl,
          'https://uat.ndid.srisawadpower.com/idp-logos/_default.svg');
      // false => the gateway's shared placeholder glyph, not this IdP's artwork.
      expect(idp.hasLogo, isFalse);
    });

    test('a real bank logo reads has_logo true', () {
      final idp = NdidIdp.fromJson(const {
        'id': 'D3443131-514B-427F-98B7-B772691D8DD9',
        'display_name': 'Kiatnakin Phatra Bank Plc.',
        'display_name_th': 'ธนาคารเกียรตินาคินภัทร จำกัด (มหาชน)',
        'logo_url': 'https://uat.ndid.srisawadpower.com/idp-logos/001_069.jpg',
        'has_logo': true,
      });
      expect(idp.hasLogo, isTrue);
      expect(idp.logoUrl, endsWith('001_069.jpg'));
    });

    test('the DAP node sends no logo fields, and that must not throw', () {
      // The compile-time fallback gateway predates logos; a tile then falls
      // back to its short code instead of an image.
      final idp = NdidIdp.fromJson(const {
        'id': 'idp1',
        'display_name': 'IdP 1',
        'display_name_th': 'บริษัท ดิจิทัล แอคเซส แพลตฟอร์ม',
      });
      expect(idp.logoUrl, isEmpty);
      expect(idp.hasLogo, isFalse);
    });

    test('id falls back to node_id, and Thai name to the English one', () {
      final idp = NdidIdp.fromJson(const {
        'node_id': 'idp4',
        'display_name': 'IdP 4',
      });
      expect(idp.id, 'idp4');
      expect(idp.displayNameTh, 'IdP 4');
    });
  });

  /// The gateway owns the customer-facing Transaction Ref as of 2026-08-31: it
  /// generates the value, appends the `(Transaction Ref: …)` clause to the
  /// Request Message the IdP app shows, and returns it as `transaction_ref`.
  /// `ndid_verify_page` displays exactly what comes back — so these pin that it
  /// is actually read off both responses. Dropping either reader would put a
  /// dash on the waiting screen while the bank's app quotes a number, which is
  /// the mismatch NDID rejected the app review over.
  group('transaction_ref', () {
    test('is read off the poll response', () {
      final status = NdidVerifyStatus.fromJson(const {
        'reference_id': '9bcc18bb-9bb4-4302-8c48-514a17c08e08',
        'transaction_ref': '000123456',
        'status': 'PENDING',
        'response_list': <dynamic>[],
      });
      expect(status.transactionRef, '000123456');
      expect(status.isPending, isTrue);
    });

    test('survives an accepted response, alongside the error-code digging', () {
      final status = NdidVerifyStatus.fromJson(const {
        'transaction_ref': '987654321',
        'status': 'ACCEPTED',
        'response_list': [
          {'aal': 2.2, 'ial': 2.3, 'idp_id': 'idp1', 'status': 'accept'},
        ],
      });
      expect(status.transactionRef, '987654321');
      expect(status.isAccepted, isTrue);
      expect(status.errorCode, isNull);
    });

    test('reads null when the gateway sends none, or sends it empty', () {
      // The DAP/SIT node predates the field. The screen shows a dash rather
      // than inventing a reference the customer's bank never displayed.
      expect(
          NdidVerifyStatus.fromJson(const {'status': 'PENDING'}).transactionRef,
          isNull);
      expect(
          NdidVerifyStatus.fromJson(
                  const {'status': 'PENDING', 'transaction_ref': '  '})
              .transactionRef,
          isNull);
    });

    test('tolerates the camelCase spelling', () {
      // The gateway is snake_case everywhere, but this field is new.
      expect(
          NdidVerifyStatus.fromJson(
                  const {'status': 'PENDING', 'transactionRef': '55555'})
              .transactionRef,
          '55555');
    });

    test('a gateway value is still checked against the standard', () {
      // isValid is what the waiting screen uses to decide whether to leave a
      // breadcrumb: the format rule (p.38) now applies to the backend's value,
      // and a 12-hex reference is exactly what was rejected.
      expect(NdidTransactionRef.isValid('000123456'), isTrue);
      expect(NdidTransactionRef.isValid('8CB4B22F15A4'), isFalse);
    });
  });
}
