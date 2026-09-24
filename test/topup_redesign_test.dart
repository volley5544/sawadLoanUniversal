import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sawad_loan_universal/p_loan/application/models/loan_contract.dart';
import 'package:sawad_loan_universal/topup/components/topup_redesign.dart';
import 'package:sawad_loan_universal/topup/models/topup_flow.dart';

void main() {
  // เลขที่สัญญา stays on one line, ellipsised (2026-09-24). The header is
  // shared by the card and the amount screen.
  testWidgets('a long contract number is ellipsised, not wrapped',
      (tester) async {
    const longNo = '000ฮฮM690801000004NFX-EXTRA-LONG-CONTRACT-NUMBER';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 420,
            child: TopupContractHeader(
              loanTypeCode: 'M',
              loanTypeName: 'สินเชื่อ',
              contractNo: longNo,
              collateralInformation: 'กข 1234',
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.text(longNo));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  group('formatTopupMoney — always two decimals', () {
    test('groups thousands', () {
      expect(formatTopupMoney(91000), '91,000.00');
      expect(formatTopupMoney(176400), '176,400.00');
    });

    test('keeps the satang the wire sends', () {
      expect(formatTopupMoney(82574.87), '82,574.87');
      expect(formatTopupMoney(8374.13), '8,374.13');
      expect(formatTopupMoney(2.49), '2.49');
    });

    test('signs a negative once, outside the grouping', () {
      expect(formatTopupMoney(-82574.87), '-82,574.87');
    });

    test('small and zero values still carry both decimals', () {
      expect(formatTopupMoney(0), '0.00');
      expect(formatTopupMoney(51), '51.00');
      expect(formatTopupMoney(999), '999.00');
      expect(formatTopupMoney(1000), '1,000.00');
    });

    // The card shows offered − principal − duty and then the same figure in
    // the strip; rows that round independently stop adding up.
    test('the design\'s own arithmetic renders consistently', () {
      const offered = 91000.0;
      const principal = 82574.87;
      const duty = 51.0;
      expect(formatTopupMoney(offered - principal - duty), '8,374.13');
    });

    test('the M35 case adds the special limit before deducting', () {
      const offered = 91000.0 + 5000;
      expect(formatTopupMoney(offered - 82574.87 - 53), '13,372.13');
    });
  });

  group('TopupContractHeader.iconFor', () {
    test('maps the loan types the design draws', () {
      expect(TopupContractHeader.iconFor('M'),
          isNot(TopupContractHeader.iconFor('C')));
      expect(TopupContractHeader.iconFor('L'),
          TopupContractHeader.iconFor('H'));
    });

    test('an unknown code gets the neutral mark, not a guess', () {
      expect(TopupContractHeader.iconFor('ZZ'),
          isNot(TopupContractHeader.iconFor('C')));
      expect(TopupContractHeader.iconFor(''),
          TopupContractHeader.iconFor('ZZ'));
    });

    test('matching is case-insensitive', () {
      expect(TopupContractHeader.iconFor('m'),
          TopupContractHeader.iconFor('M'));
    });
  });

  // TopupConditionsCard is a near-copy of TopupConditionsPanel — the _old card
  // page still renders the original, so the redesign restyles rather than
  // mutates. Duplicated wording can drift, so it is pinned here; when the _old
  // pages are deleted the original goes with them and this becomes the only
  // copy.
  group('TopupConditionsCard wording', () {
    test('both bullets are the manual\'s, verbatim', () {
      expect(TopupConditionsCard.bullets, [
        'จ่ายตรง -> เครดิตดี -> ได้วงเงินเพิ่ม',
        'จ่ายช้า -> ขอปรับสัญญาที่สาขา -> รักษาเครดิต -> ปรับวงเงินเพิ่ม',
      ]);
    });

    test('all three notes survive, with their asterisk levels', () {
      expect(TopupConditionsCard.notes, hasLength(3));
      expect(TopupConditionsCard.notes[0], startsWith('* '));
      expect(TopupConditionsCard.notes[1], startsWith('** '));
      expect(TopupConditionsCard.notes[2], startsWith('*** '));
    });

    test('the business hours are stated, since the API enforces them', () {
      expect(TopupConditionsCard.notes.first, contains('07.00 - 20.30'));
    });
  });

  group('TopupDetail.ineligibleDetail — the Code : line', () {
    TopupDetail parse(Map<String, dynamic> json) => TopupDetail.fromJson(json);

    // ⚠ **It is `can_topup_reason_code`** since 2026-09-23 (it was
    // `can_topup_msg` bare from 2026-09-19). The card prefixes `Code : `.
    test('reads can_topup_reason_code, not can_topup_msg', () {
      final d = parse({
        'can_topup': 'N',
        'can_topup_type': 'ไม่เข้าเงื่อนไข',
        'can_topup_msg': 'ระบบขัดข้อง กรุณาติดต่อสาขา',
        'can_topup_reason_code': 'contract_not_found_in_vloan',
      });
      expect(d.ineligibleDetail, 'contract_not_found_in_vloan');
      // can_topup_msg still reaches the amount screen's note.
      expect(d.canTopupMsg, 'ระบบขัดข้อง กรุณาติดต่อสาขา');
    });

    test('the old guessed keys grant nothing', () {
      expect(parse({'can_topup_code': 'E204'}).ineligibleDetail, isEmpty);
      expect(parse({'code': 'E204'}).ineligibleDetail, isEmpty);
    });

    // Empty draws no line at all — a bare `Code :` tells a branch nothing.
    test('absent renders empty, so the card draws no line at all', () {
      expect(parse({'can_topup': 'N', 'can_topup_msg': 'x'}).ineligibleDetail,
          isEmpty);
    });
  });

  group('TopupFlow.canTopupMessage — the note above the amount buttons', () {
    TopupFlow flowWith(Map<String, dynamic>? topupDetail) {
      final flow = TopupFlow(hashThaiId: 'HASH', authToken: 'TOKEN');
      if (topupDetail != null) {
        flow.contract = LoanContract.fromJson({
          'contract_no': 'C-1',
          'db_name': 'MLOAN',
          'topup_detail': topupDetail,
        });
      }
      return flow;
    }

    const guarantor =
        'สัญญามีผู้ค้ำกรุณาติดต่อสาขาเพื่อทำรายการเติมเงินพร้อมกับผู้ค้ำ';

    test('needs BOTH an ineligible contract and a message', () {
      expect(
        flowWith({'can_topup': 'N', 'can_topup_msg': guarantor})
            .canTopupMessage,
        guarantor,
      );
    });

    test('an ELIGIBLE contract shows nothing, message or not', () {
      // ⚠ The note explains a refusal, so above a working ชำระเงิน button it
      // would read as one where there is none.
      final flow = flowWith({'can_topup': 'Y', 'can_topup_msg': guarantor});
      expect(flow.contract!.isEligible, isTrue);
      expect(flow.canTopupMessage, isEmpty);
    });

    test('an ineligible contract with no message shows nothing', () {
      expect(flowWith({'can_topup': 'N'}).canTopupMessage, isEmpty);
      expect(
        flowWith({'can_topup': 'N', 'can_topup_msg': '   '}).canTopupMessage,
        isEmpty,
      );
      expect(flowWith(null).canTopupMessage, isEmpty,
          reason: 'no contract loaded yet');
    });

    test('a blank can_topup counts as ineligible, like the routing does', () {
      // `'' != 'Y'`, and TopupFlow.outcome treats it the same way — the two
      // read one resolved value (canTopupFlag) so they cannot disagree about
      // whether this contract is eligible.
      final flow = flowWith({'can_topup_msg': guarantor});
      expect(flow.canTopupFlag, isNot('Y'));
      expect(flow.canTopupMessage, guarantor);
    });

    test('still appears on the ชำระเงิน / ปรับปรุงยอดชำระ pair', () {
      // ⚠ Ineligible does not mean the buttons are gone: outcome checks unpaid
      // interest FIRST, so this contract keeps that pair — which is exactly
      // where the note was asked to appear.
      final flow = flowWith({
        'can_topup': 'N',
        'can_topup_msg': guarantor,
        'interest_paid_flag': 'Y',
      });
      expect(flow.outcome, TopupOutcome.payInterest);
      expect(flow.canTopupMessage, guarantor);
    });
  });

  group('TopupDetail.ineligibleReason — the can_topup = N second line', () {
    TopupDetail parse(Map<String, dynamic> json) => TopupDetail.fromJson(json);

    // ⚠ **Always the fixed guidance** (reverted 2026-09-19). It carried
    // `can_topup_msg` for five days; that value now renders on the `Code :`
    // line, and a card showing it in both places would say the same thing
    // twice — a live sample reads "ระบบขัดข้อง กรุณาติดต่อสาขา", which is
    // already the guidance.
    test('is the branch line whatever the API sends', () {
      expect(parse({'can_topup': 'N'}).ineligibleReason,
          TopupDetail.contactBranchFallback);
      expect(
        parse({'can_topup': 'N', 'can_topup_msg': 'ระบบขัดข้อง กรุณาติดต่อสาขา'})
            .ineligibleReason,
        TopupDetail.contactBranchFallback,
      );
    });

    test('the message is still parsed, for the code line', () {
      expect(parse({'can_topup_msg': 'ระบบขัดข้อง'}).canTopupMsg, 'ระบบขัดข้อง');
    });
  });
}
