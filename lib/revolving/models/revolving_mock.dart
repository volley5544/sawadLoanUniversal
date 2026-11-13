/// **บัตรศรีสวัสดิ์ (revolving)** — the view model every revolving screen
/// renders from, and the demo data that fills it.
///
/// **Field mapping (2026-11-12)** — from the BA's *[Mobile][RVL][Integration]
/// Loan details* and *Withdrawal process* specs (git-ignored
/// `etc/revolving_feature/screen-mapping/`). The BA names LMS APIs; this app
/// reads node-api's equivalents:
///
/// | BA's API | Here |
/// | --- | --- |
/// | `getRevolvingInfo` | `/loan/list` → `revolving_loans` ([LoanContract.revolvingLoan]) |
/// | `getMobileWithdrawal` | `GET revolvingLoan/withdrawal/{contract_id}` ([RevolvingWithdrawalInfo]) |
/// | `getRevolvingPaymentSchedule` | ⚠ **no node-api route** — its two fields render `-` |
///
/// The one exception is `maximumRevolvingLimit` (วงเงินอนุมัติ), which the BA
/// puts on `getRevolvingInfo` but `/loan/list` does not carry; it is read off
/// the withdrawal summary instead ([withWithdrawalInfo]).
///
/// [RevolvingCardView.mock] keeps the design's own figures, for the
/// plain-browser demo and screens opened without a card.
library;

import '../../loan_detail/components/loan_detail_components.dart';
import '../../p_loan/application/components/p_loan_components.dart';
import '../../p_loan/application/models/loan_contract.dart';
import 'revolving_withdrawal.dart';

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

  /// A row from an API date (`withdrawal_date`): `15 ม.ค. 69` under
  /// `มกราคม 69`, Thai time. An unreadable date is `-` under `-`.
  factory RevolvingHistoryEntry.fromDate(String raw, double amount) {
    final t = revolvingThaiTime(raw);
    if (t == null) {
      return RevolvingHistoryEntry(
          monthLabel: '-', dateLabel: '-', amount: amount);
    }
    return RevolvingHistoryEntry(
      monthLabel: '${_kMonthsLong[t.month - 1]} ${_yy(t)}',
      dateLabel: '${t.day} ${_kMonthsShort[t.month - 1]} ${_yy(t)}',
      amount: amount,
    );
  }
}

/// A label/value row (contract info, payment breakdown).
class RevolvingRow {
  const RevolvingRow(this.label, this.value);

  final String label;
  final String value;
}

/// Everything the revolving screens show about one card.
///
/// A `null` figure is one with no source yet; screens render it `-`.
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
    this.contractId = 0,
    this.revolvingStatus = '',
    this.maximumWithdrawal = 0,
    this.remainingDailyAvailableLimit = 0,
    this.remainingRequestLimit = 0,
    this.withdrawalExpiryDate = '',
    this.serverNow = '',
    this.withdrawalInfoLoaded = false,
    this.isDemo = false,
    this.contractComcode = '',
    this.loanTypeCode = '',
    this.branchCode = '',
    this.contract,
  });

  /// The `/loan/list` row this card was built from — handed to `/loanPayment`
  /// as its seed so ชำระเงิน doesn't fetch the list again. `null` on the demo.
  final LoanContract? contract;

  /// `/loan/list` `branch_code` — sent as the withdrawal's
  /// `requesting_branch` (decided 2026-11-12).
  final String branchCode;

  /// `barcode_details.comcode` and `contract_details.loan_type_code` — what
  /// the loan detail screen's สัญญาเงินกู้ rule keys on, reused for this
  /// screen's link ([revolvingContractDocumentUrl]).
  final String contractComcode;
  final String loanTypeCode;

  /// The design's figures ([RevolvingCardView.mock]) rather than a customer's
  /// contract — only a demo card shows ดูบิล's mock statement.
  final bool isDemo;

  final String contractNo;

  /// `revolving_loans.contract_id` — the numeric LMS id every
  /// `revolvingLoan/*` call is keyed by (not [contractNo]). 0 on the mock.
  final int contractId;

  /// `บัตรศรีสวัสดิ์ รถมอเตอร์ไซค์`.
  final String title;

  /// Short plate for the card header (`กพ 5161`).
  final String plate;

  /// Long plate, as the confirm/success screens print it (`5กพ 5161`).
  final String plateLong;

  /// วงเงินคงเหลือ — `revolving_loans.revolving_limit`.
  final double? availableLimit;

  /// วงเงินอนุมัติ — the withdrawal summary's `maximum_revolving_limit`;
  /// `null` until that call lands.
  final double? approvedLimit;

  /// ยอดที่แนะนำให้ชำระ — `getRevolvingPaymentSchedule.revolvingMinPay`,
  /// which node-api does not expose: `null` on a real card.
  final double? suggestedPayment;

  /// กำหนดชำระ — `getRevolvingPaymentSchedule.dueDate`; `-` on a real card
  /// for the same reason.
  final String dueDateLabel;

  /// `05 มี.ค. 69, 10:08 น.` — shown as `ข้อมูลวันที่ …` under every title.
  final String dataDateLabel;

  /// `05/03/2569 เวลา 10.08 น.` — the contract-info footer.
  final String contractInfoDateLabel;

  /// ประวัติการถอน/โอน. `null` = not loaded yet (or the load failed).
  final List<RevolvingHistoryEntry>? withdrawals;

  /// ประวัติการชำระ. `null` = no source: neither spec maps it.
  final List<RevolvingHistoryEntry>? payments;

  /// ข้อมูลสัญญา rows, in order. The last one, สัญญาเงินกู้, is a link and is
  /// rendered separately.
  final List<RevolvingRow> contractInfo;

  /// `minimum_withdrawal_amount`.
  final double minimumWithdrawal;

  /// `maximum_withdrawal_amount` — per withdrawal.
  final double maximumWithdrawal;

  /// `remaining_daily_available_limit` — money still withdrawable today.
  final double remainingDailyAvailableLimit;

  /// `remaining_request_limit` — withdrawals left today (a count).
  final int remainingRequestLimit;

  /// `revolving_status` — only `Active` may withdraw.
  final String revolvingStatus;

  /// The withdrawal summary's `withdrawal_expiry_date`.
  final String withdrawalExpiryDate;

  /// Whether `revolvingLoan/withdrawal/{id}` has been read into this card.
  final bool withdrawalInfoLoaded;

  /// The server's clock off `/loan/list` (`payment_details.current_date_time`),
  /// for the expiry check. Empty → the device clock.
  final String serverNow;

  /// ค่าธรรมเนียม on the confirm/success screens. No field carries it yet.
  final double? transferFee;

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

  /// How much of the line is drawn, 0–1, for the progress bar. 0 while
  /// either limit is unknown.
  double get usedRatio {
    final approved = approvedLimit, available = availableLimit;
    if (approved == null || available == null || approved <= 0) return 0;
    final used = (approved - available) / approved;
    return used.clamp(0, 1).toDouble();
  }

  /// The amount chips under a withdrawal amount field.
  static const List<double> quickAmounts = [500, 1000, 1500, 2000];

  // ── withdrawal rules ─────────────────────────────────────────────────

  /// Why this card cannot withdraw at all, or `null` — the card-level half
  /// of the spec's amount validation: `revolvingStatus = Active`,
  /// `remainingRequestLimit > 0` and `today ≤ withdrawalExpiryDate`.
  ///
  /// ⚠ An empty or unreadable expiry date **refuses** (blank is silence, not
  /// permission), and so does an expiry not yet loaded.
  String? withdrawalBlock([DateTime? today]) {
    final status = revolvingStatus.trim().toLowerCase();
    if (status != 'active') {
      return switch (status) {
        'soft block' => 'วงเงินถูกระงับชั่วคราว ไม่สามารถถอนเงินได้',
        'hard block' => 'วงเงินถูกระงับ ไม่สามารถถอนเงินได้',
        _ => 'สถานะวงเงินไม่พร้อมให้ถอนเงิน',
      };
    }
    if (remainingRequestLimit <= 0) {
      return 'วันนี้ทำรายการถอนเงินครบจำนวนครั้งแล้ว';
    }
    final expiry = DateTime.tryParse(withdrawalExpiryDate.trim());
    if (expiry == null) return 'ไม่พบวันสิ้นสุดการถอนเงินของวงเงินนี้';
    final now = today ?? DateTime.tryParse(serverNow.trim()) ?? DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final last = DateTime(expiry.year, expiry.month, expiry.day);
    if (day.isAfter(last)) return 'วงเงินนี้หมดระยะเวลาการถอนเงินแล้ว';
    return null;
  }

  /// Why [amount] cannot be withdrawn, or `null` when it can — the spec's
  /// whole list: the [withdrawalBlock] checks, then `amount ≥ minimum`,
  /// `≤ maximum`, `≤ revolvingLimit` and `≤ remainingDailyAvailableLimit`.
  /// An amount of 0 (nothing typed yet) reports only a card-level block.
  String? withdrawalRefusal(double amount, [DateTime? today]) {
    final block = withdrawalBlock(today);
    if (block != null) return block;
    if (amount <= 0) return null;
    if (amount < minimumWithdrawal) {
      return 'จำนวนเงินขั้นต่ำ ${_whole(minimumWithdrawal)} บาท';
    }
    if (amount > maximumWithdrawal) {
      return 'ถอนได้สูงสุด ${_whole(maximumWithdrawal)} บาทต่อครั้ง';
    }
    if (amount > (availableLimit ?? 0)) {
      return 'จำนวนเงินเกินวงเงินคงเหลือ';
    }
    if (amount > remainingDailyAvailableLimit) {
      return 'วันนี้ถอนได้อีกไม่เกิน ${_whole(remainingDailyAvailableLimit)} บาท';
    }
    return null;
  }

  /// Whether [amount] passes every rule.
  bool canWithdraw(double amount, [DateTime? today]) =>
      amount > 0 && withdrawalRefusal(amount, today) == null;

  RevolvingCardView copyWith({
    String? contractNo,
    String? title,
    String? plate,
    String? plateLong,
    bool? billReady,
    List<RevolvingBankAccount>? bankAccounts,
  }) =>
      _copy(
        contractNo: contractNo,
        title: title,
        plate: plate,
        plateLong: plateLong,
        billReady: billReady,
        bankAccounts: bankAccounts,
      );

  RevolvingCardView _copy({
    String? contractNo,
    String? title,
    String? plate,
    String? plateLong,
    bool? billReady,
    List<RevolvingBankAccount>? bankAccounts,
    double? approvedLimit,
    List<RevolvingHistoryEntry>? withdrawals,
    List<RevolvingRow>? contractInfo,
    String? withdrawalExpiryDate,
    bool? withdrawalInfoLoaded,
  }) =>
      RevolvingCardView(
        contractNo: contractNo ?? this.contractNo,
        contractId: contractId,
        title: title ?? this.title,
        plate: plate ?? this.plate,
        plateLong: plateLong ?? this.plateLong,
        availableLimit: availableLimit,
        approvedLimit: approvedLimit ?? this.approvedLimit,
        suggestedPayment: suggestedPayment,
        dueDateLabel: dueDateLabel,
        dataDateLabel: dataDateLabel,
        contractInfoDateLabel: contractInfoDateLabel,
        withdrawals: withdrawals ?? this.withdrawals,
        payments: payments,
        contractInfo: contractInfo ?? this.contractInfo,
        minimumWithdrawal: minimumWithdrawal,
        maximumWithdrawal: maximumWithdrawal,
        remainingDailyAvailableLimit: remainingDailyAvailableLimit,
        remainingRequestLimit: remainingRequestLimit,
        revolvingStatus: revolvingStatus,
        withdrawalExpiryDate: withdrawalExpiryDate ?? this.withdrawalExpiryDate,
        withdrawalInfoLoaded: withdrawalInfoLoaded ?? this.withdrawalInfoLoaded,
        isDemo: isDemo,
        contractComcode: contractComcode,
        loanTypeCode: loanTypeCode,
        branchCode: branchCode,
        contract: contract,
        serverNow: serverNow,
        transferFee: transferFee,
        bankAccounts: bankAccounts ?? this.bankAccounts,
        billReady: billReady ?? this.billReady,
        billIssueDate: billIssueDate,
        billDueDate: billDueDate,
        billUrl: billUrl,
      );

  /// One card per `/loan/list` contract whose `revolving_loans.revolving_flag`
  /// is true, its figures from `revolving_loans` (the BA's
  /// `getRevolvingInfo`). วงเงินอนุมัติ, the expiry date and the withdrawal
  /// history arrive later through [withWithdrawalInfo]; until then they are
  /// `-` / loading. ยอดที่แนะนำให้ชำระ, กำหนดชำระ, ค่าธรรมเนียม and the
  /// payment history have no source and stay `-`.
  ///
  /// ⚠ ดูบิล needs `createFileRequest`, which node-api lacks; a real card's
  /// ดูบิล says "not yet" (see `revolving_bill.dart`).
  factory RevolvingCardView.fromContract(LoanContract contract) {
    final type = contract.contractDetails.loanTypeName.trim();
    final plate = contract.contractDetails.collateralInformation.trim();
    final r = contract.revolvingLoan;
    final mock = RevolvingCardView.mock();
    return RevolvingCardView(
      contractNo: contract.contractNo.trim(),
      contractId: r.contractId,
      title: type.isEmpty ? 'บัตรศรีสวัสดิ์' : 'บัตรศรีสวัสดิ์ $type',
      plate: plate.isEmpty ? '-' : plate,
      plateLong: plate.isEmpty ? '-' : plate,
      availableLimit: r.revolvingLimit,
      approvedLimit: null,
      suggestedPayment: null,
      dueDateLabel: '-',
      dataDateLabel: revolvingDataDateLabel(contract.dataDate),
      contractInfoDateLabel: revolvingContractInfoDateLabel(contract.dataDate),
      withdrawals: null,
      payments: null,
      contractInfo: _contractRows(contract, approvedLimit: null),
      minimumWithdrawal: r.minimumWithdrawalAmount,
      maximumWithdrawal: r.maximumWithdrawalAmount,
      remainingDailyAvailableLimit: r.remainingDailyAvailableLimit,
      remainingRequestLimit: r.remainingRequestLimit,
      revolvingStatus: r.revolvingStatus,
      serverNow: contract.paymentDetails.currentDateTime,
      contractComcode: contract.barcodeDetails.comcode.trim(),
      loanTypeCode: contract.contractDetails.loanTypeCode.trim(),
      branchCode: contract.branchCode.trim(),
      contract: contract,
      transferFee: null,
      bankAccounts: r.bankAccounts,
      billReady: mock.billReady,
      billIssueDate: mock.billIssueDate,
      billDueDate: mock.billDueDate,
    );
  }

  /// This card with `revolvingLoan/withdrawal/{id}` folded in: วงเงินอนุมัติ
  /// (`maximum_revolving_limit`), `withdrawal_expiry_date` and the
  /// withdrawal history (`withdrawal_date` + `withdrawal_amount`, in the
  /// API's order).
  RevolvingCardView withWithdrawalInfo(RevolvingWithdrawalInfo info) {
    final approved = info.summary.maximumRevolvingLimit;
    return _copy(
      approvedLimit: approved,
      withdrawals: [
        for (final t in info.transactions)
          RevolvingHistoryEntry.fromDate(t.withdrawalDate, t.withdrawalAmount),
      ],
      contractInfo: [
        for (final row in contractInfo)
          row.label == 'วงเงินอนุมัติ'
              ? RevolvingRow(row.label, _amountRow(approved))
              : row,
      ],
      withdrawalExpiryDate: info.summary.withdrawalExpiryDate,
      withdrawalInfoLoaded: true,
    );
  }

  /// ข้อมูลสัญญา for a real card — the BA's *Contract detail* spec
  /// (2026-11-12):
  ///
  /// | Row | BA field | Here |
  /// | --- | --- | --- |
  /// | วงเงินอนุมัติ | `getRevolvingInfo.maximumRevolvingLimit` | withdrawal summary `maximum_revolving_limit` |
  /// | ยอดชำระขั้นต่ำ | `getRevolvingPaymentSchedule.revolvingMinPay` | ⏳ route pending → `-` |
  /// | วันครบกำหนดชำระ | `getRevolvingPaymentSchedule.dueDate` (`2026-03-20` → `ทุกวันที่ 20`) | ⏳ route pending → `-` |
  /// | วันที่ทำสัญญา | existing API | `/loan/list` `contract_date` |
  /// | ถอนได้สูงสุด/ครั้ง | `maximumWithdrawal` | `maximum_withdrawal_amount` |
  /// | ถอนขั้นต่ำ/ครั้ง | `minimumWithdrawal` | `minimum_withdrawal_amount` |
  /// | จำนวนครั้งที่ถอนได้/วัน | `remainingRequestLimit` | `remaining_request_limit` |
  /// | วงเงินคงเหลือ | `revolvingLimit` | `revolving_limit` |
  /// | ยอดเงินที่ถอนไป | `utilizationAmount` | `utilization_amount` |
  /// | สัญญาเงินกู้ | existing API | the loan detail screen's document link ([revolvingContractDocumentUrl]) |
  static List<RevolvingRow> _contractRows(LoanContract c,
      {required double? approvedLimit}) {
    final r = c.revolvingLoan;
    return [
      RevolvingRow('วงเงินอนุมัติ', _amountRow(approvedLimit)),
      const RevolvingRow('ยอดชำระขั้นต่ำ', '-'),
      const RevolvingRow('วันครบกำหนดชำระ', '-'),
      RevolvingRow('วันที่ทำสัญญา', thaiDateOrDash(c.contractDate)),
      RevolvingRow('ถอนได้สูงสุด/ครั้ง', _amountRow(r.maximumWithdrawalAmount)),
      RevolvingRow('ถอนขั้นต่ำ/ครั้ง', _amountRow(r.minimumWithdrawalAmount)),
      RevolvingRow('จำนวนครั้งที่ถอนได้/วัน', '${r.remainingRequestLimit} ครั้ง'),
      RevolvingRow('วงเงินคงเหลือ', _amountRow(r.revolvingLimit)),
      RevolvingRow('ยอดเงินที่ถอนไป', _amountRow(r.utilizationAmount)),
    ];
  }

  static String _amountRow(double? v) => v == null ? '-' : '${_whole(v)} บาท';

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
        maximumWithdrawal: 5000,
        remainingDailyAvailableLimit: 10000,
        remainingRequestLimit: 2,
        revolvingStatus: 'Active',
        withdrawalExpiryDate: '2099-12-31',
        withdrawalInfoLoaded: true,
        isDemo: true,
        transferFee: 3,
        // The design's two destinations, as `bank_accounts` entries.
        bankAccounts: const [
          RevolvingBankAccount(
            bankName: 'พร้อมเพย์',
            transferType: 'PROMPT_PAY_MOBILE_NUMBER',
            accountNumber: '0888888888',
            accountName: '[ชื่อ-นามสกุลผู้รับ]',
          ),
          RevolvingBankAccount(
            bankName: 'กรุงศรี',
            bankCode: 'BAY',
            transferType: 'CUSTOMER_BANK',
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

/// สัญญาเงินกู้ for a revolving contract — the loan detail screen's own rule
/// ("existing API" in the Contract detail spec): the `contract_url` portal's
/// `/contract?contno=…&comcode=…` with the **barcode** comcode, offered only
/// when `comcode_config.showsContractButton` allows that comcode and loan
/// type. `null` = not offered (no portal configured, or the rule says no).
String? revolvingContractDocumentUrl({
  required RevolvingCardView card,
  required String? contractUrl,
  required bool allowed,
}) {
  final base = contractUrl?.trim() ?? '';
  if (card.isDemo || base.isEmpty || !allowed) return null;
  return '$base/contract'
      '?contno=${Uri.encodeQueryComponent(card.contractNo.trim())}'
      '&comcode=${Uri.encodeQueryComponent(card.contractComcode)}';
}

String _whole(double v) => formatMoney(v).replaceAll('.00', '');

const List<String> _kMonthsShort = [
  'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', //
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
];
const List<String> _kMonthsLong = [
  'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน', //
  'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
];

/// An API timestamp as Thai wall-clock time. A UTC value (`…Z`) is moved to
/// UTC+7 by arithmetic rather than `toLocal()`, so a device set to another
/// zone still shows the Thai date; a zone-less value is taken as Thai time.
DateTime? revolvingThaiTime(String raw) {
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) return null;
  return parsed.isUtc ? parsed.add(const Duration(hours: 7)) : parsed;
}

String _yy(DateTime t) => ((t.year > 2200 ? t.year : t.year + 543) % 100)
    .toString()
    .padLeft(2, '0');
String _hhmm(DateTime t, String sep) =>
    '${t.hour.toString().padLeft(2, '0')}$sep${t.minute.toString().padLeft(2, '0')}';

/// `data_date` → `05 มี.ค. 69, 10:08 น.`; unreadable → `-`.
String revolvingDataDateLabel(String raw) {
  final t = revolvingThaiTime(raw);
  if (t == null) return '-';
  return '${t.day.toString().padLeft(2, '0')} ${_kMonthsShort[t.month - 1]} '
      '${_yy(t)}, ${_hhmm(t, ':')} น.';
}

/// `data_date` → `05/03/2569 เวลา 10.08 น.`; unreadable → `-`.
String revolvingContractInfoDateLabel(String raw) {
  final t = revolvingThaiTime(raw);
  if (t == null) return '-';
  final year = t.year > 2200 ? t.year : t.year + 543;
  return '${t.day.toString().padLeft(2, '0')}/'
      '${t.month.toString().padLeft(2, '0')}/$year เวลา ${_hhmm(t, '.')} น.';
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

  /// The `revolvingLoan/applyForWithdrawal` body for this draft, mapped as
  /// the *Withdrawal process* spec's confirm-button row says:
  ///
  /// | Field | From |
  /// | --- | --- |
  /// | `contract_id` | `revolving_loans.contract_id` |
  /// | `channel` | `Mobile` (what the QA history records) |
  /// | `transaction_date` | now, ISO-8601 UTC |
  /// | `requesting_branch` | `/loan/list` `branch_code` (decided 2026-11-12) |
  /// | `transfer_type` | `bank_accounts[].transfer_type` → `promptpay_phone` / `promptpay_citizen` / `customer_bank` |
  /// | `bank_code` | `bank_accounts[].bank_code`, **`customer_bank` only** |
  /// | `bank_account_number` | `bank_accounts[].account_number` — the phone / citizen id for PromptPay |
  /// | `bank_account_name` | `bank_accounts[].account_name` |
  /// | `withdrawal_amount` | the amount entered |
  ///
  /// ⚠ **Built, never sent.** Nothing calls `applyForWithdrawal` (it moves
  /// real money; the guide also requires customer verification before it),
  /// and the first-withdrawal route (`dayOneWithdrawal`) is still undecided.
  Map<String, dynamic> withdrawalRequest({DateTime? now}) {
    final type = account.withdrawalTransferType;
    return {
      'contract_id': card.contractId,
      'withdrawal': {
        'channel': 'Mobile',
        'transaction_date': (now ?? DateTime.now()).toUtc().toIso8601String(),
        'requesting_branch': card.branchCode,
        'transfer_type': type,
        'bank_code': type == 'customer_bank' ? account.bankCode.trim() : '',
        'bank_account_number': account.accountNumber.trim(),
        'bank_account_name': account.accountName.trim(),
        'withdrawal_amount': amount,
      },
    };
  }
}
