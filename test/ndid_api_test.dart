import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/services/ndid_api.dart';

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
}
