import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_flow.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_mock.dart';
import 'package:sawad_loan_universal/p_loan/application/models/p_loan_submission.dart';
import 'package:sawad_loan_universal/services/api_transport.dart';
import 'package:sawad_loan_universal/services/p_loan_contract_api.dart';

/// `PLoanContractApi.failureReport` — the dump behind the คัดลอก button on the
/// submit-error dialog.
///
/// It exists because an HTTP **500** rendered as `ส่งคำขอไม่สำเร็จ (HTTP 500)`
/// and nothing else: the body, which is where a 500 says what broke, was
/// decoded, found to carry no `error` key, and discarded. So what these tests
/// actually pin is that the body survives to the screen **whole** — a truncated
/// stack trace or a summarised HTML page would put the bug straight back.
void main() {
  final url = Uri.parse('https://dev.swpfin.com:7076/ploan');

  group('failure report', () {
    test('carries the response body verbatim and untruncated', () {
      // Longer than any sane excerpt, and with the cause at the very end —
      // exactly where truncation would remove it.
      final body =
          '${'<html><body><pre>' * 200}java.lang.NullPointerException: at '
          'PloanController.save(line 42)</pre></body></html>';
      final report = PLoanContractApi.failureReport(
        url,
        PLoanContractSubmission.fromFlow(_flow()),
        res: ApiHttpResult(statusCode: 500, body: body),
      );

      expect(report, contains(body));
      expect(report, contains('HTTP 500'));
      expect(report, contains('POST $url'));
      expect(report, contains('NullPointerException'));
      expect(report, isNot(contains('…')));
    });

    test('names the request so a pasted body says which submit it came from',
        () {
      final report = PLoanContractApi.failureReport(
        url,
        PLoanContractSubmission.fromFlow(_flow()),
        res: const ApiHttpResult(statusCode: 500, body: 'boom'),
      );
      // Counts, not values: the full body is behind the payload button, and
      // this text is meant to be pasteable into a chat.
      expect(report, contains('31 fields'));
      expect(report, contains('5 file parts'));
      expect(report, isNot(contains('1160200006026')));
    });

    test('lists the response headers when the transport supplied them', () {
      final report = PLoanContractApi.failureReport(
        url,
        PLoanContractSubmission.fromFlow(_flow()),
        res: const ApiHttpResult(
          statusCode: 500,
          body: 'boom',
          headers: {'content-type': 'text/html', 'server': 'nginx'},
        ),
      );
      expect(report, contains('content-type: text/html'));
      expect(report, contains('server: nginx'));
    });

    test('says headers are unavailable rather than implying none were sent',
        () {
      // The host bridge answers `{status, body}` only. "No headers section" and
      // "the server sent no headers" are different findings.
      final report = PLoanContractApi.failureReport(
        url,
        PLoanContractSubmission.fromFlow(_flow()),
        res: const ApiHttpResult(statusCode: 500, body: 'boom'),
      );
      expect(report, contains('host bridge does not return them'));
    });

    test('labels an empty body instead of trailing off', () {
      // A 500 with no body at all is its own diagnosis — usually the gateway,
      // not the app. It must not look like a dump that failed to render.
      final report = PLoanContractApi.failureReport(
        url,
        PLoanContractSubmission.fromFlow(_flow()),
        res: const ApiHttpResult(statusCode: 500, body: '   '),
      );
      expect(report, contains('(empty)'));
      expect(report, contains('response body (3 chars)'));
    });

    test('a transport failure still names the URL the build reached', () {
      // No HTTP response to dump, but which gateway was called is the whole
      // question when a submit never lands.
      final report = PLoanContractApi.failureReport(
        url,
        PLoanContractSubmission.fromFlow(_flow()),
        transportError: 'unreachable: Failed to fetch',
      );
      expect(report, contains('POST $url'));
      expect(report, contains('unreachable: Failed to fetch'));
      expect(report, isNot(contains('response body')));
    });

    test('reports the fields that went out blank', () {
      final flow = _flow()..ndidReferenceId = '';
      final report = PLoanContractApi.failureReport(
        url,
        PLoanContractSubmission.fromFlow(flow),
        res: const ApiHttpResult(statusCode: 500, body: 'boom'),
      );
      expect(report, contains('blank: '));
      expect(report, contains('ndid_reference_id'));
    });
  });
}

Uint8List _bytes(int seed) =>
    Uint8List.fromList(List<int>.generate(16, (i) => (seed + i) % 256));

/// A flow that reaches submit — the same shape `p_loan_submission_test` builds.
PLoanFlow _flow() {
  final contract =
      mockContracts().firstWhere((c) => c.contractDetails.loanTypeCode == 'M');
  final plan = mockInstallmentPlan(30000);
  final flow = PLoanFlow(
    hashThaiId: 'HASH',
    kind: PLoanKind.extra,
    authToken: 'TOKEN',
    source: 'app',
    referId: 'REF',
    customer: mockCustomer(),
    contract: contract,
    amountDetail: mockAmountDetail(contract.contractNo),
  )
    ..requestedAmount = 30000
    ..plan = plan
    ..documents = mockDocuments()
    ..ndidReferenceId = '9bcc18bb-9bb4-4302-8c48-514a17c08e08'
    ..sensitiveConsent = true;
  flow.installment = plan.installments.firstWhere((i) => i.tenor == 24);
  flow.photos[PLoanPhoto.idCard] = _bytes(20);
  flow.photos[PLoanPhoto.selfieWithIdCard] = _bytes(30);
  return flow;
}
