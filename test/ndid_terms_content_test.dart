import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/loan_register/ndid_terms_content.dart';

/// The agreement is legal text the customer accepts, and it is generated out of
/// the supplied Pages document rather than retyped. These pin the shape that
/// extraction produced, so a re-run — or a hand edit — cannot quietly drop a
/// clause or leave the source document's own numbering in the body text.
void main() {
  group('NDID terms content', () {
    test('carries clauses 1-9 exactly once, in the document order', () {
      final numbers = kNdidTermsClauses.map((c) => c.number).toList();
      expect(numbers, <String>['1', '2', '3', '4', '5', '6', '7', '8', '9']);
    });

    test('every clause has body text', () {
      for (final clause in kNdidTermsClauses) {
        expect(clause.paragraphs, isNotEmpty,
            reason: 'clause ${clause.number} has no paragraphs');
        for (final p in clause.paragraphs) {
          expect(p.trim(), isNotEmpty,
              reason: 'clause ${clause.number} has a blank paragraph');
        }
      }
    });

    test('clause 3 keeps its five sub-items, and no other clause has any', () {
      for (final clause in kNdidTermsClauses) {
        if (clause.number == '3') {
          expect(clause.items.map((i) => i.marker).toList(),
              <String>['(1)', '(2)', '(3)', '(4)', '(5)']);
          for (final item in clause.items) {
            expect(item.text.trim(), isNotEmpty);
          }
        } else {
          expect(clause.items, isEmpty,
              reason: 'clause ${clause.number} gained sub-items');
        }
      }
    });

    test('the numbering the source document carried is not left in the body '
        'text', () {
      // Clauses 3, 4 and 6-9 carried a literal "3.<tab>" prefix in the .pages
      // file while 1, 2 and 5 were auto-numbered and carried none. The
      // extraction strips them so [NdidTermsClause.number] is the only source
      // of a clause number — otherwise clause 3 renders as "3. 3. เมื่อ...".
      for (final clause in kNdidTermsClauses) {
        expect(clause.paragraphs.first, isNot(startsWith('${clause.number}.')),
            reason: 'clause ${clause.number} repeats its own number');
        expect(clause.paragraphs.first, isNot(contains('\t')));
      }
      for (final item in kNdidTermsClauses.expand((c) => c.items)) {
        expect(item.text, isNot(startsWith(item.marker)));
        expect(item.text, isNot(contains('\t')));
      }
    });

    test('names the issuer the agreement is with', () {
      expect(kNdidTermsTitle, contains('ข้อตกลง'));
      expect(kNdidTermsIssuer, contains('ศรีสวัสดิ์'));
    });
  });
}
