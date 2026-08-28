import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/loan_register/ndid_terms_page.dart';

/// Renders the agreement screen at a phone size. The clauses are long enough
/// that a layout mistake shows up as an overflow rather than as bad wording,
/// and `flutter test` fails on an overflow — so pumping a frame is the check.
void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: NdidTermsPage()));
    await tester.pump();
  }

  testWidgets('renders the agreement heading and both answers', (tester) async {
    await pump(tester);

    expect(find.text('เงื่อนไขและข้อตกลงที่เกี่ยวข้อง NDID'), findsOneWidget);
    // The document's own heading, above the clauses.
    expect(find.textContaining('ข้อตกลงในการใช้บริการพิสูจน์'), findsOneWidget);
    expect(find.text('ปฏิเสธ'), findsOneWidget);
    expect(find.text('ยอมรับ'), findsOneWidget);
    // The first clause is on screen without any scrolling.
    expect(find.textContaining('ข้อตกลงและเงื่อนไขนี้'), findsOneWidget);
  });

  // The whole agreement has to be reachable by scrolling — it is what the
  // customer is accepting. `scrollUntilVisible` fails outright if the target
  // never appears, so this walks from clause 3's sub-items to the last clause.
  testWidgets('scrolls from the first clause through to the last',
      (tester) async {
    await pump(tester);

    final list = find.byType(Scrollable);

    for (final marker in <String>['(1)', '(2)', '(3)', '(4)', '(5)']) {
      await tester.scrollUntilVisible(find.text(marker), 300, scrollable: list);
      expect(find.text(marker), findsOneWidget, reason: 'sub-item $marker');
    }

    // Clause 9, the end of the document.
    await tester.scrollUntilVisible(
        find.textContaining('ข้อมูลชีวภาพ'), 300, scrollable: list);
    expect(find.textContaining('ข้อมูลชีวภาพ'), findsOneWidget);

    // The answers stay put while the agreement scrolls under them.
    expect(find.text('ปฏิเสธ'), findsOneWidget);
    expect(find.text('ยอมรับ'), findsOneWidget);
  });
}
