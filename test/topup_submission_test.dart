import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/services/api_transport.dart';
import 'package:sawad_loan_universal/services/topup_api.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_contract.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_documents.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_mock.dart';
import 'package:sawad_loan_universal/topup/models/topup_flow.dart';
import 'package:sawad_loan_universal/topup/models/topup_lead_submission.dart';
import 'package:sawad_loan_universal/topup/models/topup_photo.dart';
import 'package:sawad_loan_universal/topup/models/topup_purpose.dart';
import 'package:sawad_loan_universal/topup/models/topup_submission.dart';

/// The exact key set `POST /topup` takes, transcribed from the source's
/// `SaveNewTopupCall` body. Pinned so the mapper and the wire cannot drift:
/// an added key has to be added here too, deliberately.
const Set<String> _topupFields = {
  'transno',
  'db_name',
  'hash_thai_id',
  'contract_no',
  'life_insure_amt',
  'marketing_consent',
  'sensitive_consent',
  'latitude',
  'longitude',
  'loan_amount',
  'topup_fee',
  'fee_amount',
  'transfer_amount',
  'interest_rate',
  'interest_amount',
  'total_amount',
  'credit_limit',
  'term_period',
  'regular_period',
  'last_period',
  'last_period_promo',
  'act_image',
  'property_image',
  'car_image_front',
  'car_image_back',
  'car_image_left',
  'car_image_right',
  'car_image_mile',
  'customer_image_2',
  'customer_image_3',
  'topup_request_file',
  'topup_receipt_file',
  'topup_argeement_file',
  'save_pdf',
  'source',
  'refer_id',
  'product_code',
};

TopupFlow _completeFlow({
  bool? marketing,
  bool? sensitive,
  String contractNo = 'MOCK-C-6701002',
}) {
  final base =
      mockContracts().firstWhere((c) => c.contractNo == contractNo).rawJson;
  final contract = LoanContract.fromJson({
    ...base,
    'topup_detail': {
      ...(base['topup_detail'] as Map<String, dynamic>),
      'max_transfer_amount': 5000000,
    },
  });
  final detail = mockAmountDetail(contractNo);
  final plan = mockInstallmentPlan(detail.defaultTopupAmount);
  final flow = TopupFlow(
    hashThaiId: 'HASH123',
    authToken: 'TOKEN',
    source: 'LH_WEB',
    referId: 'REF-9',
  )
    ..contract = contract
    ..customer = mockCustomer()
    ..amountDetail = detail.copyWith(feeAmount: plan.feeAmount)
    ..requestedAmount = detail.defaultTopupAmount
    ..plan = plan
    ..documents = mockDocuments()
    ..verifiedThaiId = mockCustomer().thaiId
    // `null` leaves TopupFlow's own defaults in place, so a test can prove
    // what an untouched flow actually files.
    ..marketingConsent = marketing ?? true
    ..sensitiveConsent = sensitive ?? true
    ..latitude = '13.7563000'
    ..longitude = '100.5017600';
  flow.installment = plan.installments.first;
  flow.consentedDocuments.addAll(LoanDocumentKind.values);
  final bytes = Uint8List.fromList([9, 9, 9]);
  for (final slot in [...flow.requiredPhotos, ...TopupPhoto.identity]) {
    flow.photos[slot] = bytes;
  }
  return flow;
}

void main() {
  group('POST /topup body', () {
    test('produces exactly the API\'s key set — no more, no less', () {
      final fields = TopupSubmission.fromFlow(_completeFlow()).fields;
      expect(fields.keys.toSet(), _topupFields);
    });

    test('carries the misspelled agreement key the API really uses', () {
      final fields = TopupSubmission.fromFlow(_completeFlow()).fields;
      expect(fields.containsKey('topup_argeement_file'), isTrue);
      expect(fields.containsKey('topup_agreement_file'), isFalse);
    });

    test('transfer_amount is the payout, principal and duty deducted', () {
      final flow = _completeFlow();
      final fields = TopupSubmission.fromFlow(flow).fields;
      expect(fields['transfer_amount'], flow.payoutAmount);
      expect(
        fields['transfer_amount'],
        flow.calculatedAmount - flow.closingBalance - flow.feeAmount,
      );
    });

    test('fee_amount is the calculator\'s, not /topup/detail\'s', () {
      final flow = _completeFlow();
      final fields = TopupSubmission.fromFlow(flow).fields;
      expect(fields['fee_amount'], flow.plan!.feeAmount);
    });

    group('PDPA consents are the customer\'s answers, not a hardcoded Y', () {
      test('both given', () {
        final fields = TopupSubmission.fromFlow(
          _completeFlow(marketing: true, sensitive: true),
        ).fields;
        expect(fields['marketing_consent'], 'Y');
        expect(fields['sensitive_consent'], 'Y');
      });

      test('marketing declined goes out as N', () {
        // The source sent 'Y' for both unconditionally, recording a marketing
        // consent the customer was never asked for.
        final fields =
            TopupSubmission.fromFlow(_completeFlow(marketing: false)).fields;
        expect(fields['marketing_consent'], 'N');
      });

      test('N is a real answer, so it is never reported as unresolved', () {
        final submission = TopupSubmission.fromFlow(
          _completeFlow(marketing: false),
        );
        expect(submission.unresolvedFields, isNot(contains('marketing_consent')));
      });

      // ⚠ End to end, because the tests above set both booleans explicitly and
      // would keep passing if the flow's defaults were flipped. Step 7's
      // ความยินยอม checkboxes are commented out — the host's /consent page
      // asks instead — so what an *untouched* flow files is the only thing a
      // customer can now produce, and it must be Y for both (confirmed
      // 2026-09-17).
      test('an untouched flow files Y for both, as the consent page recorded',
          () {
        final fields = TopupSubmission.fromFlow(_completeFlow()).fields;
        expect(fields['marketing_consent'], 'Y');
        expect(fields['sensitive_consent'], 'Y');
      });
    });

    test('photos travel as data URLs', () {
      final fields = TopupSubmission.fromFlow(_completeFlow()).fields;
      expect(fields['customer_image_2'],
          startsWith('data:image/jpeg;base64,'));
      expect(
        fields['customer_image_2'],
        'data:image/jpeg;base64,${base64Encode([9, 9, 9])}',
      );
    });

    test('a slot this loan type never asks for is blank, not reported', () {
      // A car needs no whole-vehicle shot, so property_image is empty by
      // design — reporting it would send a tester chasing a non-problem.
      final submission = TopupSubmission.fromFlow(_completeFlow());
      expect(submission.fields['property_image'], '');
      expect(submission.unresolvedFields, isNot(contains('property_image')));
      expect(submission.unresolvedFields, isEmpty);
    });

    test('a missing required photo IS reported', () {
      final flow = _completeFlow()..photos.remove(TopupPhoto.carMile);
      final submission = TopupSubmission.fromFlow(flow);
      expect(submission.unresolvedFields, contains('car_image_mile'));
    });

    test('coordinates are accepted blank — capture is never awaited', () {
      final flow = _completeFlow()
        ..latitude = ''
        ..longitude = '';
      final submission = TopupSubmission.fromFlow(flow);
      // Present as fields, but not chased: a denied permission or a cold GPS
      // must not stop an application being filed.
      expect(submission.fields.containsKey('latitude'), isTrue);
      expect(submission.unresolvedFields, isEmpty);
    });

    test('save_pdf matches the /pdf/loan request that made the documents', () {
      final flow = _completeFlow();
      final fields = TopupSubmission.fromFlow(flow).fields;
      expect(fields['save_pdf'], flow.pdfRequest!.toJson());
    });

    test('product_code follows the chosen purpose', () {
      final flow = _completeFlow()
        ..purpose = const TopupPurpose(
          productCode: 'INS001',
          productName: 'ประกันภัย',
          productDescription: '',
          productPrice: 3000,
        );
      expect(TopupSubmission.fromFlow(flow).fields['product_code'], 'INS001');
    });

    test('no purpose sends an EMPTY product_code, never OTR001', () {
      // OTR001 is the source's "อื่นๆ" row in its วัตถุประสงค์ list — a UI
      // value for a screen this build removed on 2026-09-11 — and the source
      // itself sends `''` whenever no product was chosen:
      //   products == ProductsStruct() ? '' : products.productCode
      // ⚠ Changed while chasing a 501 that turned out to be contract-specific
      // (it reproduces on the old app too), so this pins the source match, not
      // a fix for that error.
      final flow = _completeFlow();
      expect(flow.purpose, isNull, reason: 'เติมวงเงิน picks no product');
      final code = TopupSubmission.fromFlow(flow).fields['product_code'];
      expect(code, '');
      expect(code, isNot(kTopupOtherProductCode));
    });

    test('an incomplete flow throws rather than filing a partial request', () {
      final flow = _completeFlow()..installment = null;
      expect(() => TopupSubmission.fromFlow(flow), throwsStateError);
    });
  });

  group('lead body', () {
    test('forwards the contract\'s own sub-objects untouched', () {
      final flow = _completeFlow();
      final fields = TopupLeadSubmission.fromFlow(flow).fields;
      expect(
        fields['contract_details'],
        same(flow.contract!.rawJson['contract_details']),
      );
      expect(fields['contract_no'], flow.contract!.contractNo);
      expect(fields['hash_thai_id'], 'HASH123');
      expect(fields['utm_source'], 'LH_WEB');
      expect(fields['utm_campaign'], 'REF-9');
    });

    test('claims no PDPA consent, because a lead never reaches that screen',
        () {
      final fields = TopupLeadSubmission.fromFlow(_completeFlow()).fields;
      expect(fields['pdpa_flg'], '');
      expect(fields['pdpa_date'], '');
    });

    test('without a contract it throws rather than filing an empty lead', () {
      final flow = TopupFlow(hashThaiId: 'H', authToken: 'T');
      expect(() => TopupLeadSubmission.fromFlow(flow), throwsStateError);
    });
  });

  group('TopupApi.failureReport', () {
    final url = Uri.parse('https://api/topup');

    test('carries both the request and the response', () {
      // An HTTP 400 against 37 fields is unactionable without seeing which of
      // them went out; a 500 is usually an HTML page whose last line is why.
      final report = TopupApi.failureReport(
        url,
        {'contract_no': 'C-1', 'topup_amount': 20000},
        res: const ApiHttpResult(statusCode: 400, body: '{"message":"bad"}'),
      );
      expect(report, contains('POST https://api/topup'));
      expect(report, contains('HTTP 400'));
      expect(report, contains('contract_no'));
      expect(report, contains('C-1'));
      expect(report, contains('{"message":"bad"}'));
    });

    test('elides base64 by size, keeping every scalar verbatim', () {
      // ⚠ Nine photos and three PDFs would be tens of megabytes — unreadable,
      // unpasteable, and enough to hang the dialog. The scalars are what a 400
      // is actually about.
      final report = TopupApi.failureReport(
        url,
        {
          'contract_no': 'C-1',
          'act_image': 'A' * 40000,
          'topup_request_file': 'B' * 8000,
        },
        res: const ApiHttpResult(statusCode: 400, body: 'x'),
      );
      expect(report, contains('C-1'));
      expect(report, isNot(contains('A' * 600)));
      expect(report, contains('elided'));
      // The size survives, because that is the debuggable part of a photo.
      expect(report, contains('KB'));
    });

    test('elides by length, not by key name', () {
      // A photo field added later must not dump megabytes before anyone
      // notices it is missing from a list of known keys.
      final report = TopupApi.failureReport(
        url,
        {'some_future_image': 'Z' * 40000},
        res: const ApiHttpResult(statusCode: 500, body: ''),
      );
      expect(report, contains('elided'));
      expect(report, isNot(contains('Z' * 600)));
    });

    test('the response body is never truncated', () {
      // On a 500 the cause is often the last line, which is exactly what a cap
      // would remove.
      final long = List.generate(400, (i) => 'line $i').join('\n');
      final report = TopupApi.failureReport(url, const {},
          res: ApiHttpResult(statusCode: 500, body: long));
      expect(report, contains('line 0'));
      expect(report, contains('line 399'));
    });

    test('a transport failure names itself and still shows the request', () {
      final report = TopupApi.failureReport(url, {'contract_no': 'C-1'},
          transportError: 'unreachable: boom');
      expect(report, contains('transport error: unreachable: boom'));
      expect(report, contains('C-1'));
      expect(report, isNot(contains('HTTP ')));
    });

    test('an empty response body says so rather than showing nothing', () {
      final report = TopupApi.failureReport(url, const {},
          res: const ApiHttpResult(statusCode: 502, body: ''));
      expect(report, contains('(empty)'));
    });
  });

}
