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

import '../../p_loan/application/models/loan_contract.dart';

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
    required this.contractInfo,
    required this.minimumWithdrawal,
    required this.transferFee,
    required this.bankAccounts,
    required this.billReady,
    required this.billIssueDate,
    required this.billDueDate,
    this.billUrl = '',
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

  /// ข้อมูลสัญญา rows, in order. The last one, สัญญาเงินกู้, is a link and is
  /// rendered separately.
  final List<RevolvingRow> contractInfo;

  final double minimumWithdrawal;
  final double transferFee;

  /// Where a withdrawal can go — `revolving_loans.bank_accounts`, one
  /// selector tile per entry, in the order the backend sends them. A single
  /// entry means a single tile; none means no destination to offer.
  final List<RevolvingBankAccount> bankAccounts;

  /// Whether this cycle's statement has been issued (ถึงวันสรุปยอด).
  final bool billReady;
  final String billIssueDate;
  final String billDueDate;

  /// Where the issued statement lives. The API will send it as a URL and the
  /// app opens it in the host's in-app browser (`openExternalUrl`). Empty
  /// until the API exists.
  final String billUrl;

  /// How much of the line is drawn, 0–1, for the progress bar.
  double get usedRatio {
    if (approvedLimit <= 0) return 0;
    final used = (approvedLimit - availableLimit) / approvedLimit;
    return used.clamp(0, 1).toDouble();
  }

  /// The amount chips under a withdrawal amount field.
  static const List<double> quickAmounts = [500, 1000, 1500, 2000];

  RevolvingCardView copyWith({
    String? contractNo,
    String? title,
    String? plate,
    String? plateLong,
    bool? billReady,
    List<RevolvingBankAccount>? bankAccounts,
  }) =>
      RevolvingCardView(
        contractNo: contractNo ?? this.contractNo,
        title: title ?? this.title,
        plate: plate ?? this.plate,
        plateLong: plateLong ?? this.plateLong,
        availableLimit: availableLimit,
        approvedLimit: approvedLimit,
        suggestedPayment: suggestedPayment,
        dueDateLabel: dueDateLabel,
        dataDateLabel: dataDateLabel,
        contractInfoDateLabel: contractInfoDateLabel,
        withdrawals: withdrawals,
        payments: payments,
        contractInfo: contractInfo,
        minimumWithdrawal: minimumWithdrawal,
        transferFee: transferFee,
        bankAccounts: bankAccounts ?? this.bankAccounts,
        billReady: billReady ?? this.billReady,
        billIssueDate: billIssueDate,
        billDueDate: billDueDate,
        billUrl: billUrl,
      );

  /// One card per `/loan/list` contract whose `revolving_loans.revolving_flag`
  /// is true (2026-11-12).
  ///
  /// ⚠ **Only the identity is real**: contract number, title (from
  /// `loan_type_name`), plate (`collateral_information`) and
  /// `bank_accounts`. Every figure, the history and the contract-info rows
  /// are still the design's [RevolvingCardView.mock] values, the same on
  /// every card, until the revolving data is wired. A missing value is `-`.
  factory RevolvingCardView.fromContract(LoanContract contract) {
    final type = contract.contractDetails.loanTypeName.trim();
    final plate = contract.contractDetails.collateralInformation.trim();
    return RevolvingCardView.mock().copyWith(
      contractNo: contract.contractNo.trim(),
      title: type.isEmpty ? 'บัตรศรีสวัสดิ์' : 'บัตรศรีสวัสดิ์ $type',
      plate: plate.isEmpty ? '-' : plate,
      plateLong: plate.isEmpty ? '-' : plate,
      bankAccounts: contract.revolvingLoan.bankAccounts,
    );
  }

  /// The customer's revolving contracts, in `/loan/list` order, as cards.
  static List<RevolvingCardView> listFrom(List<LoanContract> contracts) => [
        for (final c in contracts)
          if (c.revolvingLoan.revolvingFlag) RevolvingCardView.fromContract(c),
      ];

  /// Which card to open on: the one whose contract the host passed in
  /// `?contNo=` (a loan card's ถอนเงิน), else the first (the home-menu
  /// บัตรศรีสวัสดิ์ tile). Both sides trimmed, like the top-up card's
  /// preselect.
  static int initialIndex(List<RevolvingCardView> cards, String contractNo) {
    final wanted = contractNo.trim();
    if (wanted.isEmpty) return 0;
    final i = cards.indexWhere((c) => c.contractNo.trim() == wanted);
    return i < 0 ? 0 : i;
  }

  /// Plain-browser demo (no `hashThaiId`): two design cards, so switching
  /// can be seen without a customer.
  static List<RevolvingCardView> demo({String contractNo = ''}) => [
        RevolvingCardView.mock(contractNo: contractNo),
        RevolvingCardView.mock(contractNo: 'DEMO-2').copyWith(
          title: 'บัตรศรีสวัสดิ์ รถยนต์',
          plate: 'ขก 1234',
          plateLong: '1ขก 1234',
        ),
      ];

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
        // The design's two destinations, as `bank_accounts` entries.
        bankAccounts: const [
          RevolvingBankAccount(
            bankName: 'พร้อมเพย์',
            transferType: 'promptpay_phone',
            accountNumber: '0888888888',
            accountName: '[ชื่อ-นามสกุลผู้รับ]',
          ),
          RevolvingBankAccount(
            bankName: 'กรุงศรี',
            bankCode: 'BAY',
            transferType: 'customer_bank',
            accountType: 'SAVING ACCOUNT',
            accountNumber: '1234567890',
            accountName: '[ชื่อ-นามสกุลผู้รับ]',
            isDefault: true,
          ),
        ],
        billReady: false,
        billIssueDate: '2026-11-03',
        billDueDate: '2026-11-06',
      );
}

/// What a withdrawal screen hands to its confirm / success screens.
class RevolvingTransferDraft {
  const RevolvingTransferDraft({
    required this.card,
    required this.account,
    required this.amount,
  });

  final RevolvingCardView card;

  /// The `bank_accounts` entry the customer picked.
  final RevolvingBankAccount account;
  final double amount;
}
