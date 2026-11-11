/// **บัตรศรีสวัสดิ์ (revolving)** — the view model every revolving screen
/// renders from, and the demo data that fills it.
///
/// ⚠ **UI only (2026-11-11).** No endpoint is wired yet: every screen renders
/// [RevolvingCardView.mock], whose figures are copied from the BA design
/// (`etc/revolving_feature/…User Manual AppSrisawad_10-11-2026…pdf`) so the
/// screens can be compared against it side by side. When the APIs land, build
/// a [RevolvingCardView] from `LoanContract.revolvingLoan` (+ whatever the
/// history / bill / transfer endpoints return) and no screen changes.
library;

/// One withdrawal or payment row in a history tab.
class RevolvingHistoryEntry {
  const RevolvingHistoryEntry({
    required this.monthLabel,
    required this.dateLabel,
    required this.amount,
  });

  /// Group heading, e.g. `มกราคม 69`.
  final String monthLabel;

  /// Row heading, e.g. `15 ม.ค. 69`.
  final String dateLabel;
  final double amount;
}

/// A label/value row (contract info, payment breakdown).
class RevolvingRow {
  const RevolvingRow(this.label, this.value);

  final String label;
  final String value;
}

/// Where a withdrawal is sent.
enum RevolvingTransferTarget {
  /// พร้อมเพย์ — to the customer's phone number or citizen id.
  promptPay,

  /// บัญชีธนาคารที่ผูกไว้ — to the bank account bound to the contract.
  bankAccount,
}

/// Everything the revolving screens show about one card.
class RevolvingCardView {
  const RevolvingCardView({
    required this.contractNo,
    required this.title,
    required this.plate,
    required this.plateLong,
    required this.availableLimit,
    required this.approvedLimit,
    required this.suggestedPayment,
    required this.dueDateLabel,
    required this.dataDateLabel,
    required this.contractInfoDateLabel,
    required this.withdrawals,
    required this.payments,
    required this.suggestedBreakdown,
    required this.contractInfo,
    required this.minimumWithdrawal,
    required this.transferFee,
    required this.bankName,
    required this.bankShortCode,
    required this.bankAccountNo,
    required this.bankAccountMasked,
    required this.accountHolderPlaceholder,
    required this.payerPlaceholder,
    required this.promptPayPhone,
    required this.promptPayCitizenId,
    required this.billReady,
    required this.billIssueDate,
    required this.billDueDate,
    this.billUrl = '',
    required this.qrRef1,
    required this.qrRef2,
  });

  final String contractNo;

  /// `บัตรศรีสวัสดิ์ รถมอเตอร์ไซค์`.
  final String title;

  /// Short plate for the card header (`กพ 5161`).
  final String plate;

  /// Long plate, as the confirm/success screens print it (`5กพ 5161`).
  final String plateLong;

  /// วงเงินคงเหลือ.
  final double availableLimit;

  /// วงเงินอนุมัติ.
  final double approvedLimit;

  /// ยอดที่แนะนำให้ชำระ.
  final double suggestedPayment;

  /// `20 มี.ค. 69` — shown as `กำหนดชำระ …`.
  final String dueDateLabel;

  /// `05 มี.ค. 69, 10:08 น.` — shown as `ข้อมูลวันที่ …` under every title.
  final String dataDateLabel;

  /// `05/03/2569 เวลา 10.08 น.` — the contract-info footer.
  final String contractInfoDateLabel;

  final List<RevolvingHistoryEntry> withdrawals;
  final List<RevolvingHistoryEntry> payments;

  /// ยอดที่แนะนำชำระ breakdown (วันครบกำหนดชำระ … รวม).
  final List<RevolvingRow> suggestedBreakdown;

  /// ข้อมูลสัญญา rows, in order. The last one, สัญญาเงินกู้, is a link and is
  /// rendered separately.
  final List<RevolvingRow> contractInfo;

  final double minimumWithdrawal;
  final double transferFee;

  final String bankName;
  final String bankShortCode;
  final String bankAccountNo;
  final String bankAccountMasked;
  final String accountHolderPlaceholder;
  final String payerPlaceholder;
  final String promptPayPhone;
  final String promptPayCitizenId;

  /// Whether this cycle's statement has been issued (ถึงวันสรุปยอด).
  final bool billReady;
  final String billIssueDate;
  final String billDueDate;

  /// Where the issued statement lives. The API will send it as a URL and the
  /// app opens it in the host's in-app browser (`openExternalUrl`). Empty
  /// until the API exists.
  final String billUrl;

  final String qrRef1;
  final String qrRef2;

  /// How much of the line is drawn, 0–1, for the progress bar.
  double get usedRatio {
    if (approvedLimit <= 0) return 0;
    final used = (approvedLimit - availableLimit) / approvedLimit;
    return used.clamp(0, 1).toDouble();
  }

  /// The amount chips under a withdrawal amount field.
  static const List<double> quickAmounts = [500, 1000, 1500, 2000];

  RevolvingCardView copyWith({bool? billReady}) => RevolvingCardView(
        contractNo: contractNo,
        title: title,
        plate: plate,
        plateLong: plateLong,
        availableLimit: availableLimit,
        approvedLimit: approvedLimit,
        suggestedPayment: suggestedPayment,
        dueDateLabel: dueDateLabel,
        dataDateLabel: dataDateLabel,
        contractInfoDateLabel: contractInfoDateLabel,
        withdrawals: withdrawals,
        payments: payments,
        suggestedBreakdown: suggestedBreakdown,
        contractInfo: contractInfo,
        minimumWithdrawal: minimumWithdrawal,
        transferFee: transferFee,
        bankName: bankName,
        bankShortCode: bankShortCode,
        bankAccountNo: bankAccountNo,
        bankAccountMasked: bankAccountMasked,
        accountHolderPlaceholder: accountHolderPlaceholder,
        payerPlaceholder: payerPlaceholder,
        promptPayPhone: promptPayPhone,
        promptPayCitizenId: promptPayCitizenId,
        billReady: billReady ?? this.billReady,
        billIssueDate: billIssueDate,
        billDueDate: billDueDate,
        billUrl: billUrl,
        qrRef1: qrRef1,
        qrRef2: qrRef2,
      );

  /// The design's own figures.
  factory RevolvingCardView.mock({String contractNo = ''}) =>
      RevolvingCardView(
        contractNo: contractNo,
        title: 'บัตรศรีสวัสดิ์ รถมอเตอร์ไซค์',
        plate: 'กพ 5161',
        plateLong: '5กพ 5161',
        availableLimit: 10000,
        approvedLimit: 50000,
        suggestedPayment: 2500.25,
        dueDateLabel: '20 มี.ค. 69',
        dataDateLabel: '05 มี.ค. 69, 10:08 น.',
        contractInfoDateLabel: '05/03/2569 เวลา 10.08 น.',
        withdrawals: const [
          RevolvingHistoryEntry(
              monthLabel: 'มกราคม 69', dateLabel: '15 ม.ค. 69', amount: 500),
          RevolvingHistoryEntry(
              monthLabel: 'กุมภาพันธ์ 69', dateLabel: '3 ก.พ. 69', amount: 1000),
          RevolvingHistoryEntry(
              monthLabel: 'กุมภาพันธ์ 69',
              dateLabel: '20 ก.พ. 69',
              amount: 1438),
          RevolvingHistoryEntry(
              monthLabel: 'มีนาคม 69', dateLabel: '4 มี.ค. 69', amount: 800),
        ],
        payments: const [
          RevolvingHistoryEntry(
              monthLabel: 'มกราคม 69',
              dateLabel: '20 ม.ค. 69',
              amount: 1213.35),
          RevolvingHistoryEntry(
              monthLabel: 'กุมภาพันธ์ 69',
              dateLabel: '18 ก.พ. 69',
              amount: 1438),
        ],
        suggestedBreakdown: const [
          RevolvingRow('วันครบกำหนดชำระ', '20/05/2569'),
          RevolvingRow('ดอกเบี้ย+เงินต้น', '2,450.25 บาท'),
          RevolvingRow('ค่าติดตาม', '50.00 บาท'),
          RevolvingRow('รวม', '2,500.25 บาท'),
        ],
        contractInfo: const [
          RevolvingRow('วงเงินอนุมัติ', '50,000 บาท'),
          RevolvingRow('ยอดชำระขั้นต่ำ', '500 บาท'),
          RevolvingRow('วันครบกำหนดชำระ', 'ทุกวันที่ 20'),
          RevolvingRow('วันที่ทำสัญญา', '13/02/2569'),
          RevolvingRow('ถอนได้สูงสุด/ครั้ง', '5,000 บาท'),
          RevolvingRow('ถอนขั้นต่ำ/ครั้ง', '500 บาท'),
          RevolvingRow('จำนวนครั้งที่ถอนได้/วัน', '2 ครั้ง'),
          RevolvingRow('วงเงินคงเหลือ', '10,000 บาท'),
          RevolvingRow('ยอดเงินที่ถอนไป', '40,000 บาท'),
        ],
        minimumWithdrawal: 500,
        transferFee: 3,
        bankName: 'กรุงศรี',
        bankShortCode: 'BAY',
        bankAccountNo: '123-4-56789-0',
        bankAccountMasked: 'XXX-X-XXXXX-X',
        accountHolderPlaceholder: '[ชื่อ-นามสกุลผู้รับ]',
        payerPlaceholder: '[ชื่อ-นามสกุลผู้จ่าย]',
        promptPayPhone: '088-888-8888',
        promptPayCitizenId: '1-2345-67890-12-3',
        billReady: false,
        billIssueDate: '2026-11-03',
        billDueDate: '2026-11-06',
        qrRef1: '000000016677690401',
        qrRef2: '00004787088057',
      );
}

/// What a withdrawal screen hands to its confirm / success screens.
class RevolvingTransferDraft {
  const RevolvingTransferDraft({
    required this.card,
    required this.target,
    required this.amount,
    this.promptPayUsesPhone = true,
  });

  final RevolvingCardView card;
  final RevolvingTransferTarget target;
  final double amount;

  /// พร้อมเพย์ only: phone number (true) or citizen id (false).
  final bool promptPayUsesPhone;
}

/// What the payment screen hands to its confirm / success screens.
class RevolvingPaymentDraft {
  const RevolvingPaymentDraft({required this.card, required this.amount});

  final RevolvingCardView card;
  final double amount;
}
