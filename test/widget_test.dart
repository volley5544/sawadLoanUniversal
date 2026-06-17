// Smoke test: the app boots straight into the loan-register list page.

import 'package:flutter_test/flutter_test.dart';

import 'package:sawad_loan_universal/main.dart';

void main() {
  testWidgets('App launches to the loan-register list page',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    // App bar title of LoanRegisterListPage.
    expect(find.text('รายการ'), findsOneWidget);
    // The primary action button.
    expect(find.text('ถัดไป'), findsOneWidget);
  });
}
