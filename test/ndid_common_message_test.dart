import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/services/ndid_api.dart';
import 'package:sawad_loan_universal/services/ndid_common_message.dart';

/// NDID rejected the 2026-08-28 app review on three points; two were code:
///
/// * **issue 2** — the Transaction Ref must be RP-generated, digits only, and
///   at most 9 long. The screen was showing 12 hex characters of NDID's own
///   `ndid_request_id`.
/// * **issue 3** — IdP and AS failures must use the standard Common Message
///   wording from the NDID guideline, not messages of our own.
///
/// These pin both, because neither is enforced by anything else: a reworded
/// message still compiles and still renders, and a Transaction Ref generator
/// that drifts to 10 digits fails only at review time, months later.
void main() {
  group('Transaction Ref (NDID guideline p.38)', () {
    test('is digits only and within the 5-9 the standard allows', () {
      for (var i = 0; i < 500; i++) {
        final ref = NdidTransactionRef.generate();
        expect(RegExp(r'^[0-9]+$').hasMatch(ref), isTrue,
            reason: 'digits only, got "$ref"');
        expect(ref.length, inInclusiveRange(5, 9), reason: 'got "$ref"');
        expect(NdidTransactionRef.isValid(ref), isTrue);
      }
    });

    test('is not NDID\'s reference_id, which satisfies neither rule', () {
      // The value the screen used to show, from a real request.
      expect(NdidTransactionRef.isValid('8CB4B22F15A4'), isFalse);
      // A raw NDID reference_id.
      expect(
          NdidTransactionRef.isValid('9bcc18bb-9bb4-4302-8c48-514a17c08e08'),
          isFalse);
    });

    test('rejects lengths and alphabets outside the standard', () {
      expect(NdidTransactionRef.isValid('1234'), isFalse, reason: '4 digits');
      expect(NdidTransactionRef.isValid('1234567890'), isFalse,
          reason: '10 digits');
      expect(NdidTransactionRef.isValid('12345678A'), isFalse, reason: 'letter');
      expect(NdidTransactionRef.isValid(''), isFalse);
      expect(NdidTransactionRef.isValid('000000001'), isTrue,
          reason: "the standard's own example, leading zeros and all");
    });

    test('varies between requests', () {
      final seen = {for (var i = 0; i < 200; i++) NdidTransactionRef.generate()};
      // A constant would pass every other test here while telling the IdP the
      // same reference for every customer.
      expect(seen.length, greaterThan(100));
    });
  });

  group('Request Message (NDID guideline 6.2.1 [28])', () {
    test('names the RP and quotes the Transaction Ref', () {
      final msg = NdidCommonMessage.requestMessage(transactionRef: '000000001');
      expect(msg, contains(NdidCommonMessage.rpMarketingName));
      expect(msg, contains('Transaction Ref: 000000001'));
      expect(msg, startsWith('ท่านกำลังยืนยันตัวตนเพื่อใช้ตามวัตถุประสงค์ของ'));
    });

    test('omits the clause entirely when the gateway composes it', () {
      // Since 2026-08-31 the srisawad NDID gateway generates the Transaction Ref
      // and appends "(Transaction Ref: N)" to this message itself. Quoting one
      // of ours here would put a second, different reference in front of the
      // customer — the review failure wearing the opposite mistake.
      final msg = NdidCommonMessage.requestMessage();
      expect(msg, contains(NdidCommonMessage.rpMarketingName));
      expect(msg, isNot(contains('Transaction Ref')));
      expect(msg, isNot(endsWith(' ')), reason: 'no dangling separator');
      // An empty string is the same statement as null, not a reference.
      expect(NdidCommonMessage.requestMessage(transactionRef: ''), msg);
    });

    test('claims no Authoritative Source, because the request asks for none',
        () {
      // Mode 2 with no data_request_list: naming a bank here would tell the
      // customer their data is being fetched when it is not.
      final msg = NdidCommonMessage.requestMessage(transactionRef: '123456789');
      expect(msg, isNot(contains('ประสงค์ให้ส่งข้อมูลจาก')));
    });
  });

  group('IdP / AS Common Messages (NDID guideline 6.2.1 [10]-[27])', () {
    test('every documented code has its own message', () {
      const codes = <int>[
        30000, 30200, 30300, 30400, 30500, 30510, 30520, 30530, //
        30600, 30610, 30700, 30800, 30900, //
        40000, 40200, 40300, 40400, 40500,
      ];
      final messages = <String>{};
      for (final code in codes) {
        final msg = NdidCommonMessage.forErrorCode(code);
        expect(msg, isNotEmpty, reason: 'code $code');
        expect(msg, isNot(NdidCommonMessage.generalFailure),
            reason: 'code $code fell through to the catch-all');
        expect(msg, isNot(contains('[IdP]')),
            reason: 'code $code leaked the template placeholder');
        expect(msg, isNot(contains('XXX')),
            reason: 'code $code leaked the template contact');
        messages.add(msg);
      }
      // 40300 and 40500 share wording in the standard; everything else differs.
      expect(messages.length, codes.length - 1);
    });

    test('an unknown or missing code gets the standard catch-all', () {
      expect(NdidCommonMessage.forErrorCode(null),
          NdidCommonMessage.generalFailure);
      expect(NdidCommonMessage.forErrorCode(99999),
          NdidCommonMessage.generalFailure);
    });

    test('30900 names the provider, per 6.2.1 bullet 4', () {
      final named =
          NdidCommonMessage.forErrorCode(30900, idpName: 'ธนาคารกสิกรไทย');
      expect(named, contains('ธนาคารกสิกรไทย'));
      // With no name it must still read as a sentence, not "ของ  กรุณา".
      final unnamed = NdidCommonMessage.forErrorCode(30900);
      expect(unnamed, contains('ผู้ให้บริการยืนยันตัวตนที่ท่านเลือก'));
      expect(unnamed, isNot(contains('  ')));
    });

    test('no message tells the customer to call a placeholder number', () {
      // "RP Contact XXX" is the standard's placeholder. Until a real contact is
      // configured the messages must degrade to a generic instruction rather
      // than print it.
      for (final code in <int>[40000, 40300, 40400, 40500]) {
        final msg = NdidCommonMessage.forErrorCode(code);
        expect(msg, contains('ติดต่อ'));
        expect(msg, isNot(contains('XXX')), reason: 'code $code');
      }
    });
  });

  group('status → message', () {
    test('an error code wins over the status', () {
      expect(
        NdidCommonMessage.forStatus('IDP_OR_AS_ERROR', errorCode: 30510),
        NdidCommonMessage.forErrorCode(30510),
      );
    });

    test('a cancelled request gets the standard cancel wording', () {
      expect(NdidCommonMessage.forStatus('CANCELLED'),
          NdidCommonMessage.cancelledOrChangedIdp);
    });

    test('everything else falls back to the standard catch-all', () {
      for (final s in <String>['REJECTED', 'TIMEOUT', 'REQUESTED_ERROR', '']) {
        expect(NdidCommonMessage.forStatus(s), NdidCommonMessage.generalFailure,
            reason: s);
      }
    });
  });

  group('NdidVerifyStatus parses the error code', () {
    test('from a response_list entry, where the gateway puts it', () {
      final s = NdidVerifyStatus.fromJson(const {
        'status': 'IDP_OR_AS_ERROR',
        'response_list': [
          {'idp_id': 'idp1', 'error_code': 30510},
        ],
      });
      expect(s.status, 'IDP_OR_AS_ERROR');
      expect(s.errorCode, 30510);
      expect(s.isError, isTrue);
      expect(s.isPending, isFalse,
          reason: 'an errored request must stop the poll, not run the hour out');
    });

    test('from the envelope, and tolerating a string', () {
      expect(
        NdidVerifyStatus.fromJson(const {'status': 'REJECTED', 'error_code': '30600'})
            .errorCode,
        30600,
      );
    });

    test('absent when the request simply has not finished', () {
      final s = NdidVerifyStatus.fromJson(const {
        'status': 'PENDING',
        'response_list': [
          {'idp_id': 'idp1', 'status': 'pending'},
        ],
      });
      expect(s.errorCode, isNull);
      expect(s.isPending, isTrue);
    });

    test('an accepted request is neither pending nor an error', () {
      final s = NdidVerifyStatus.fromJson(const {
        'status': 'ACCEPTED',
        'response_list': [
          {'idp_id': 'idp1', 'status': 'accept', 'ial': 2.3, 'aal': 2.2},
        ],
      });
      expect(s.isAccepted, isTrue);
      expect(s.isPending, isFalse);
      expect(s.isError, isFalse);
      expect(s.errorCode, isNull);
    });
  });
}
