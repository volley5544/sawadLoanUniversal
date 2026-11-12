import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/components/api_failure_dialog.dart';
import 'package:sawad_loan_universal/config/app_environment.dart';
import 'package:sawad_loan_universal/services/api_transport.dart';
import 'package:sawad_loan_universal/services/srisawad_api.dart';

/// The uat failure report every บัตรศรีสวัสดิ์ call carries (2026-11-12).
void main() {
  test('report: request line with the hash masked, status, full body', () {
    final body = '<html>${'x' * 5000}last line: the cause</html>';
    final r = SrisawadApi.callReport(
      'GET',
      Uri.parse('https://qa.example/loan/list?hash_thai_id=abcdef123'),
      res: ApiHttpResult(statusCode: 500, body: body),
    );
    expect(r, contains('GET https://qa.example/loan/list'
        '?hash_thai_id=<redacted:9 chars>'));
    expect(r, isNot(contains('abcdef123')));
    expect(r, contains('HTTP 500'));
    expect(r, contains('last line: the cause')); // never truncated
  });

  test('report: request body and transport error', () {
    final r = SrisawadApi.callReport(
      'POST',
      Uri.parse('https://qa.example/revolvingLoan/checkAcceptanceFlag'),
      body: {'contract_id': 2881},
      transportError: 'timeout',
    );
    expect(r, contains('transport error: timeout'));
    expect(r, contains('"contract_id": 2881'));
    expect(r, isNot(contains('response body')));
  });

  testWidgets('uat shows the report dialog; no report → nothing', (t) async {
    // Tests run as uat (the default environment).
    expect(AppEnvironment.current.isProd, isFalse);
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold();
    })));

    showApiFailureDialog(ctx, SrisawadApiException('plain'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    showApiFailureDialog(
        ctx, SrisawadApiException('HTTP 500', details: 'GET /x\nHTTP 500'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('HTTP 500'), findsOneWidget);
    expect(find.text('GET /x\nHTTP 500'), findsOneWidget);
    expect(find.text('คัดลอก'), findsOneWidget);
  });
}
