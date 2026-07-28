/// **Provisional** installment options for a **new P-Loan**, computed on the
/// client.
///
/// TEMPORARY — the new-P-Loan product has no installment-calculator endpoint
/// yet, and the top-up calculator (`POST /topup/calculator`) can't price it:
/// its reference contract isn't a top-up candidate, so the server answers
/// `ไม่พบสัญญาใน vloan`. Until the real endpoint lands, step 3 is fed these
/// locally-computed options so the flow stays walkable.
///
/// This is deliberately **separate** from the full mock-mode fixtures in
/// `p_loan_mock.dart` (which are gated by `kPLoanUseMockData` and deleted along
/// with mock mode): this runs in the *live* flow, for the new-loan path only.
/// When `PLoanApi` gets the real call, replace `calculateNewLoanInstallments`
/// with it and delete this file — no screen changes.
library;

import 'installment_plan.dart';

/// Flat monthly interest rate (percent) used until the real product rate comes
/// from the API. A placeholder for pricing the estimate, not a quoted rate.
const double kProvisionalNewLoanMonthlyRate = 1.25;

/// Tenors offered as a placeholder. A personal loan's real tenor menu comes
/// from the pricing API; these keep step 3 populated in the meantime.
const List<int> kProvisionalNewLoanTenors = [12, 24, 36, 48, 60];

/// Builds provisional installment options for [loanAmount].
///
/// The maths is flat-rate (add-on interest): interest is charged on the whole
/// principal for the full term and split evenly across each [tenor], matching
/// how the existing mock plan is shaped so the screens parse it identically.
InstallmentPlan provisionalNewLoanPlan(
  int loanAmount, {
  double monthlyRate = kProvisionalNewLoanMonthlyRate,
  List<int> tenors = kProvisionalNewLoanTenors,
}) {
  // Stamp duty: 1 baht per 2,000 (or part thereof) of the loan — the standard
  // Thai rate. Provisional like the rest of this; the API returns the real one.
  final feeAmount = loanAmount <= 0 ? 0 : (loanAmount / 2000).ceil();

  List<Map<String, dynamic>> options() => tenors.map((tenor) {
        final interest = loanAmount * (monthlyRate / 100) * tenor;
        final total = loanAmount + interest;
        final regular = (total / tenor).floor();
        final last = total - (regular * (tenor - 1));
        return <String, dynamic>{
          'tenor': tenor,
          'firstPeriodAmt': regular,
          'regularPeriodAmt': regular,
          'lastPeriodAmt': double.parse(last.toStringAsFixed(2)),
          'totalAmt': double.parse(total.toStringAsFixed(2)),
          'intAmt': double.parse(interest.toStringAsFixed(2)),
          'lastPeriodPromo': 0.0,
          'term': '$tenor',
          'amount': '$loanAmount',
        };
      }).toList();

  // due_day / first_due_date are left unset: they depend on a real schedule the
  // pricing API assigns, and the new-P-Loan submission (PLoanContractSubmission)
  // does not send either, so a placeholder here would only mislead.
  return InstallmentPlan.fromJson({
    'code': '200',
    'message': '',
    'trans_no': '',
    'first_due_date': '',
    'due_day': 0,
    'amount': loanAmount,
    'interest_rate': monthlyRate,
    'topup_fee_amount': 0,
    'fee_amount': feeAmount,
    'installments': options(),
  });
}
