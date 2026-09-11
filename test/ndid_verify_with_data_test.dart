import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/config/app_environment.dart';
import 'package:sawad_loan_universal/models/app_config.dart';
import 'package:sawad_loan_universal/services/ndid_api.dart';
import 'package:sawad_loan_universal/services/ndid_common_message.dart';

/// `/rp/verify-with-data` (2026-09-10). Shapes pinned here come from the
/// supplied sample curl and from live reads of the prod gateway; see
/// `dap/api_curl.txt`, which is git-ignored.
void main() {
  // One AS entry exactly as `GET /services/001.cust_info_001/as` returns it:
  // no flattened fields, everything inside a JSON *string*.
  Map<String, dynamic> asJson({
    String nodeId = '8D86D107-80C3-4B2A-B928-FCB9D5833741',
    String industry = '001',
    String company = '004',
    String th = 'ธนาคารกสิกรไทย',
    String en = 'KBANK',
  }) =>
      {
        'node_id': nodeId,
        'node_name': '{"industry_code":"$industry","company_code":"$company",'
            '"marketing_name_th":"$th","marketing_name_en":"$en",'
            '"proxy_or_subsidiary_name_th":"","proxy_or_subsidiary_name_en":"",'
            '"role":"AS","running":"1"}',
        'min_ial': 2.3,
        'min_aal': 2.2,
        'supported_namespace_list': ['citizen_id'],
      };

  group('NdidAs parses the gateway shape', () {
    test('the codes and names come out of the node_name JSON string', () {
      final as = NdidAs.fromJson(asJson());
      expect(as.nodeId, '8D86D107-80C3-4B2A-B928-FCB9D5833741');
      expect(as.industryCode, '001');
      expect(as.companyCode, '004');
      expect(as.marketingNameEn, 'KBANK');
      expect(as.displayName, 'ธนาคารกสิกรไทย', reason: 'Thai is preferred');
      expect(as.minIal, 2.3);
      expect(as.minAal, 2.2);
    });

    test('a malformed node_name degrades to blanks instead of throwing', () {
      final as = NdidAs.fromJson({'node_id': 'X', 'node_name': 'not json'});
      expect(as.nodeId, 'X');
      expect(as.industryCode, isEmpty);
      expect(as.displayName, isEmpty);
    });

    test('an absent node_name is not an error either', () {
      expect(NdidAs.fromJson(const {'node_id': 'X'}).companyCode, isEmpty);
    });

    test('displayName falls back to English when there is no Thai name', () {
      final as = NdidAs.fromJson(asJson(th: ''));
      expect(as.displayName, 'KBANK');
    });
  });

  group('NdidIdp carries the institution codes that join it to an AS', () {
    test('the flattened fields /idp/list sends are read', () {
      final idp = NdidIdp.fromJson(const {
        'id': '6DDF80BD-FCF8-45A6-AB5D-0AA27586501E',
        'display_name': 'KBANK',
        'display_name_th': 'ธนาคารกสิกรไทย',
        'industry_code': '001',
        'company_code': '004',
      });
      expect(idp.industryCode, '001');
      expect(idp.companyCode, '004');
      expect(idp.hasInstitutionCode, isTrue);
    });

    test('a gateway that only sends node_name still yields the codes', () {
      final idp = NdidIdp.fromJson({
        'id': 'X',
        'display_name': 'KBANK',
        'node_name': asJson()['node_name'],
      });
      expect(idp.industryCode, '001');
      expect(idp.companyCode, '004');
    });

    test('an IdP with no codes cannot be joined, and says so', () {
      final idp = NdidIdp.fromJson(const {'id': 'X', 'display_name': 'Y'});
      expect(idp.hasInstitutionCode, isFalse);
    });
  });

  group('the AS clause is rendered only when data is actually requested', () {
    test('no AS names means no clause — the pre-2026-09-10 message', () {
      expect(
        NdidCommonMessage.requestMessage(),
        'ท่านกำลังยืนยันตัวตนเพื่อใช้ตามวัตถุประสงค์ของ'
        '${NdidCommonMessage.rpMarketingName}',
      );
    });

    test('one AS name renders the standard clause', () {
      final msg = NdidCommonMessage.requestMessage(asNames: ['ธนาคารกสิกรไทย']);
      expect(msg, contains('และประสงค์ให้ส่งข้อมูลจาก ธนาคารกสิกรไทย'));
    });

    test('the AS clause precedes the Transaction Ref, per the template', () {
      final msg = NdidCommonMessage.requestMessage(
        asNames: ['ธนาคารกสิกรไทย'],
        transactionRef: '12345678',
      );
      expect(
        msg.indexOf('ส่งข้อมูลจาก'),
        lessThan(msg.indexOf('Transaction Ref')),
      );
      // No space after the colon — p.38's template and the gateway's own
      // rendering both omit it (observed 2026-09-10).
      expect(msg, endsWith('(Transaction Ref:12345678)'));
    });

    test('several AS names are comma-joined', () {
      final msg = NdidCommonMessage.requestMessage(asNames: ['ธนาคารก', 'ธนาคารข']);
      expect(msg, contains('ส่งข้อมูลจาก ธนาคารก, ธนาคารข'));
    });

    test('blank names are dropped, never rendered as an empty slot', () {
      expect(
        NdidCommonMessage.requestMessage(asNames: const ['', '   ']),
        isNot(contains('ส่งข้อมูลจาก')),
      );
      expect(
        NdidCommonMessage.requestMessage(asNames: const ['', 'ธนาคารกสิกรไทย']),
        contains('ส่งข้อมูลจาก ธนาคารกสิกรไทย'),
      );
    });

    test('the clause carries a marketing name, never a node id', () {
      // §6.2.1 bullet 4. The guard is that callers pass NdidAs.displayName;
      // this pins that a node id would be visibly wrong if one ever leaked.
      final msg = NdidCommonMessage.requestMessage(
        asNames: [NdidAs.fromJson(asJson()).displayName],
      );
      expect(msg, isNot(contains('8D86D107')));
      expect(msg, contains('ธนาคารกสิกรไทย'));
    });
  });

  group('the data request is built from constants the gateway fixed', () {
    test('service id and callback url match the supplied curl', () {
      expect(NdidApi.dataServiceId, '001.cust_info_001');
      expect(NdidApi.dataCallbackUrl,
          'https://ndid.srisawadpower.com/ndid/callback');
      expect(NdidApi.minAs, 1);
    });

    test('the sample curl as_id is not baked in anywhere', () {
      // It is not on the prod gateway (verified 2026-09-10): all 14 AS node
      // ids differ. Resolution is by company_code, so this literal must never
      // appear in lib/.
      expect(NdidApi.dataServiceId, isNot(contains('A18AC373')));
      expect(NdidApi.dataCallbackUrl, isNot(contains('A18AC373')));
    });
  });

  group('pinned Authoritative Source (ndid_as_id)', () {
    // uat's gateway cannot resolve an AS from the chosen IdP, so the node id
    // is pinned in the config rather than compiled in — see kNdidAsId for why
    // a baked-in id is the `request_type` mistake of 2026-07-31 in a new
    // costume.
    test('reads the _uat key on a uat build', () {
      final config = AppConfig.fromDecoded(const {
        'ndid_as_id': 'PROD-AS',
        'ndid_as_id_uat': 'A18AC373-9CCB-47B3-A285-9ADBA29AFEFC',
      });
      expect(config.ndidAsId, 'A18AC373-9CCB-47B3-A285-9ADBA29AFEFC');
    });

    test('an unset pin leaves resolution to findAsForIdp', () {
      // The normal case, and the one prod must stay in: no pin configured.
      expect(const AppConfig().ndidAsId, isNull);
      expect(AppConfig.fromDecoded(const {'api_url': {}}).ndidAsId, isNull);
    });

    test('nothing ships in the bundle', () {
      // The define is the degrade-to only; the config is where a pin belongs,
      // so it stays per-environment and removable without a rebuild.
      expect(kNdidAsId, isEmpty);
      expect(kNdidAsName, isEmpty);
    });

    test('an optional name rides alongside the id', () {
      final config = AppConfig.fromDecoded(const {
        'ndid_as_id_uat': 'AS-1',
        'ndid_as_name_uat': 'ธนาคารกสิกรไทย',
      });
      expect(config.ndidAsName, 'ธนาคารกสิกรไทย');
    });

    test('a nameless AS contributes no clause to the Request Message', () {
      // Naming a source we cannot confirm is worse than naming none — §6.2.1
      // lets the wording be adjusted for clarity, not for invention.
      final message = NdidCommonMessage.requestMessage(asNames: const []);
      expect(message, isNot(contains('ประสงค์ให้ส่งข้อมูลจาก')));
    });
  });
}
