/// **รายละเอียดสินเชื่อ** — one contract, in full.
///
/// Ported from the srisawad mobile app's `loan_installment_detail_page.dart`
/// (its UI and, verbatim, its visibility rules) with the API and config wiring
/// of LandAndHouseWeb's `loan_detail_page_widget.dart`. It is the loan-universal
/// replacement for the latter, which the host opens today through
/// `api_url['loan_detail_web' | 'loan_detail_web_uat']`.
///
/// ## It makes no `loan/detail` call, deliberately
///
/// Everything on the first two tabs comes from the row `GET /loan/list`
/// already returns — `contract_details`, `payment_details`, `car_details` and
/// `insurances` are all complete there. **Both** reference clients do it this
/// way, and it is the right shape: the screen is opened from a list the
/// customer was just looking at, and a second endpoint could disagree with it.
/// Only the ประวัติการชำระ tab needs a call of its own, and it is made lazily,
/// the first time that tab is opened.
///
/// ## URL-addressable
///
/// `/loanDetail?contNo=…` (optionally `&dbName=…`), so the host can deep-link
/// it with `path: '/loanDetail', params: {'contNo': …}` on its existing
/// `/loan-universal-webview` route — which already appends `hashThaiId` and
/// `token`. Carrying the contract number rather than a model object means a
/// reload reproduces the screen instead of landing on a blank one.
///
/// ⚠ **No payment screen.** The source's ชำระเงิน button is deliberately not
/// built yet; see [_buildBottomBar].
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_state.dart';
import '../models/comcode_config.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../p_loan/application/models/loan_contract.dart';
import '../loan_payment/models/loan_payment_seed.dart';
import '../router/app_router.dart';
import '../services/app_config_api.dart';
import '../services/diagnostics.dart';
import '../services/external_url.dart';
import '../services/loan_detail_api.dart';
import '../services/native_bridge.dart';
import '../services/p_loan_api.dart';
import '../services/srisawad_api.dart';
import 'components/loan_detail_components.dart';
import 'components/loan_detail_header_card.dart';
import 'insurance_list_page.dart';
import 'models/loan_detail_summary.dart';
import 'models/payment_history_entry.dart';

/// The three tabs, in the order the source lists them.
///
/// The source has a fourth, `คู่สัญญา`, commented out of its own list: it was
/// never a tab body but a link that opened the contract portal, and that job
/// belongs to the bottom button. It is not reproduced.
enum LoanDetailTab {
  info('ข้อมูลสินเชื่อ'),
  payment('ข้อมูลการชำระ'),
  history('ประวัติการชำระ');

  const LoanDetailTab(this.label);
  final String label;
}

class LoanDetailPage extends StatefulWidget {
  const LoanDetailPage({
    super.key,
    required this.contractNo,
    this.dbName = '',
    this.fromHost = false,
  });

  /// `?contNo=` — the contract to show. Required; the row is looked up in
  /// `/loan/list`.
  final String contractNo;

  /// `?dbName=` — optional. Contract numbers are unique only **within** a
  /// database, so when the caller knows both, both are matched. LandAndHouseWeb
  /// matches on the contract number alone, which is why this is not required.
  final String dbName;

  /// `?fromHost=true` — nothing of this build's own sits beneath this screen,
  /// so back must close the WebView rather than pop to a route that isn't
  /// there. Same flag and same reason as the top-up card's.
  final bool fromHost;

  @override
  State<LoanDetailPage> createState() => _LoanDetailPageState();
}

class _LoanDetailPageState extends State<LoanDetailPage> {
  /// `loan_type_code` of a contract whose คู่สัญญา document is issued only at
  /// the branch that owns the account, never in the app. Pressing the button
  /// for one of these asks the customer to confirm they already hold it.
  static const String kBranchIssuedLoanTypeCode = 'O';

  LoanContract? _contract;
  ComcodeConfig _comcodeConfig = const ComcodeConfig();
  String? _contractUrl;
  bool _showPayButton = false;
  String? _error;

  LoanDetailTab _tab = LoanDetailTab.info;

  PaymentHistory? _history;
  String? _historyError;
  bool _historyLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _contract = null;
      _error = null;
    });

    final appState = AppState();
    if (appState.hashThaiId.isEmpty) {
      setState(() => _error =
          'ไม่พบข้อมูลผู้ใช้ กรุณาเปิดหน้านี้จากแอปพลิเคชันอีกครั้ง');
      return;
    }
    final wanted = widget.contractNo.trim();
    if (wanted.isEmpty) {
      setState(() => _error = 'ไม่พบเลขที่สัญญา');
      return;
    }

    try {
      // Through PLoanApi, not SrisawadApi directly: that is the one seam
      // carrying the `kPLoanUseMockData` guard, and a build advertising itself
      // as a mock build (every screen wears PLoanMockBanner) must not quietly
      // call the live API behind that banner. It also means the fixtures make
      // this screen demoable with no backend and no bearer token.
      final contracts = await PLoanApi.listContracts(
        hashThaiId: appState.hashThaiId,
        token: appState.authToken,
      );
      final match = _pick(contracts, wanted);
      if (match == null) {
        if (mounted) {
          setState(() => _error = 'ไม่พบสัญญาเลขที่ $wanted');
        }
        return;
      }
      // The config read is memoised and never throws, so it costs nothing on a
      // second visit and an outage leaves every rule `false` rather than
      // failing the screen.
      final config = await AppConfigApi.ensureLoaded();
      if (!mounted) return;
      setState(() {
        _contract = match;
        _comcodeConfig = config.comcodeConfig;
        _contractUrl = config.contractUrl;
        _showPayButton = config.isShowPayButton;
      });
    } on SrisawadApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// The row for [contractNo], matching [LoanDetailPage.dbName] too when the
  /// caller supplied one.
  LoanContract? _pick(List<LoanContract> contracts, String contractNo) {
    final db = widget.dbName.trim();
    for (final contract in contracts) {
      if (contract.contractNo.trim() != contractNo) continue;
      if (db.isNotEmpty && contract.dbName.trim() != db) continue;
      return contract;
    }
    return null;
  }

  void _selectTab(LoanDetailTab tab) {
    setState(() => _tab = tab);
    // Lazily, and only once: the source dispatches its history load from the
    // same place, so a customer who never opens the tab never makes the call.
    if (tab == LoanDetailTab.history &&
        _history == null &&
        !_historyLoading &&
        _historyError == null) {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    final contract = _contract;
    if (contract == null) return;
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    try {
      final history = await LoanDetailApi.fetchPaymentHistory(
        contractNo: contract.contractNo,
        dbName: contract.dbName,
        token: AppState().authToken,
      );
      if (!mounted) return;
      setState(() {
        _history = history;
        _historyLoading = false;
      });
    } on SrisawadApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = e.message;
        _historyLoading = false;
      });
    }
  }

  void _onBack() {
    if (widget.fromHost) {
      NativeCameraBridge.closeWebview();
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  // ── the contract document (คู่สัญญา / คำขอออกตั๋ว) ───────────────────

  /// `{contract_url}/contract?contno=…&comcode=…`, or null when the config
  /// names no portal — in which case the button and the download link are not
  /// offered at all, rather than opening a malformed URL.
  String? get _contractDocumentUrl {
    final contract = _contract;
    final base = _contractUrl?.trim();
    if (contract == null || base == null || base.isEmpty) return null;
    // ⚠ The **barcode** comcode, which is what both references key their
    // visibility rules on — so the value that decided the button is the value
    // in the link. (LandAndHouseWeb puts `contract_details.comcode_code` in
    // the URL instead while keying its rules on this one; if the portal ever
    // 404s, that is the first thing to try.)
    final comcode = contract.barcodeDetails.comcode.trim();
    return '$base/contract'
        '?contno=${Uri.encodeQueryComponent(contract.contractNo.trim())}'
        '&comcode=${Uri.encodeQueryComponent(comcode)}';
  }

  Future<void> _onContractDocumentPressed() async {
    final contract = _contract;
    if (contract == null) return;
    if (contract.contractDetails.loanTypeCode.trim() ==
        kBranchIssuedLoanTypeCode) {
      final acknowledged = await _confirmBranchIssuedDocument();
      if (acknowledged != true) return;
      // ⚠ The source writes a Firestore audit record here (who acknowledged,
      // when, and a best-effort GPS fix). This build has no write path — its
      // `firestore.rules` grant no client any write — so the acknowledgement
      // is only a session-local breadcrumb, readable from the `(UAT ver…)`
      // tag. See Outstanding: it needs an endpoint, not a rules change.
      Diagnostics.log(
          'contract party acknowledged ${contract.contractNo.trim()}');
    }
    await _openContractDocument();
  }

  Future<bool?> _confirmBranchIssuedDocument() => showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'คู่สัญญา',
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansThai(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: LoanDetailPalette.navy,
            ),
          ),
          content: Text(
            'กรุณาขอคู่สัญญาที่สาขาเจ้าของบัญชี หรือหากได้รับแล้วกรุณากด ตกลง',
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansThai(
              fontSize: 14,
              height: 1.5,
              color: LoanDetailPalette.label,
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'ยกเลิก',
                style: GoogleFonts.notoSansThai(
                  fontWeight: FontWeight.w600,
                  color: LoanDetailPalette.label,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'ตกลง',
                style: GoogleFonts.notoSansThai(
                  fontWeight: FontWeight.w600,
                  color: LoanDetailPalette.contractButtonText,
                ),
              ),
            ),
          ],
        ),
      );

  Future<void> _openContractDocument() async {
    final url = _contractDocumentUrl;
    if (url == null) return;
    await openExternalDocument(context, url);
  }

  // ── build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: loanDetailAppBar(context, 'รายละเอียดสินเชื่อ', onBack: _onBack),
      body: _body(),
    );
  }

  Widget _body() {
    final error = _error;
    if (error != null) return PLoanErrorView(message: error, onRetry: _load);
    final contract = _contract;
    if (contract == null) {
      return const PLoanLoadingView(message: 'กำลังโหลดรายละเอียดสินเชื่อ...');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PLoanMockBanner(),
        LoanDetailHeaderCard(
          contract: contract,
          showsNotIssuedNotice: _showsNotIssuedNotice(contract),
          onDownloadContract:
              _contractDocumentUrl == null ? null : _openContractDocument,
          onViewInsurances: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  InsuranceListPage(insurances: contract.insurances),
            ),
          ),
        ),
        Container(height: 1, color: LoanDetailPalette.divider),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                _importantNotes(context),
                Container(
                  color: LoanDetailPalette.tabBar,
                  height: 54,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final tab in LoanDetailTab.values)
                        LoanDetailTabChip(
                          label: tab.label,
                          selected: _tab == tab,
                          onTap: () => _selectTab(tab),
                        ),
                    ],
                  ),
                ),
                _tabBody(contract),
              ],
            ),
          ),
        ),
        _buildBottomBar(contract),
      ],
    );
  }

  bool _showsNotIssuedNotice(LoanContract contract) =>
      _contractDocumentUrl != null &&
      _comcodeConfig.showsContractNotIssuedNotice(
        comcode: contract.barcodeDetails.comcode,
        loanTypeCode: contract.contractDetails.loanTypeCode,
        contractNo: contract.contractNo,
        contractDate: contract.contractDate,
      );

  /// The two red blocks between the header and the tabs. Both are constant
  /// text — they are not conditional on anything.
  Widget _importantNotes(BuildContext context) {
    final width = math.min(MediaQuery.sizeOf(context).width, 500.0) * 0.9;
    final style = GoogleFonts.notoSansThai(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: LoanDetailPalette.alert,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      child: Column(
        children: [
          SizedBox(
            width: width,
            child: Text(
              '*กรณีค้างชําระ ค่างวดยังไม่รวมค่าปรับ/ค่าติดตาม\n'
              '**หากต้องปิดบัญชี กรุณาติดต่อสาขาเจ้าของบัญชี',
              textAlign: TextAlign.left,
              style: style,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: width,
            child: Text(
              'สำคัญ : กรณีชําระค่างวดไม่เต็มจํานวนที่กําหนด\n'
              'ส่งผลให้เกิดภาระดอกเบี้ยที่สูงขึ้น รวมถึงอาจต้องรับผิดชอบ'
              'ค่าใช้จ่ายในการติดตามทวงถามหนี้ และจะส่งผลให้ยอดเงินที่ต้อง'
              'ชำระในงวดสุดท้ายเพิ่มขึ้น',
              textAlign: TextAlign.left,
              style: style,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBody(LoanContract contract) => switch (_tab) {
        LoanDetailTab.info => _LoanInfoTab(contract: contract),
        LoanDetailTab.payment => _PaymentInfoTab(contract: contract),
        LoanDetailTab.history => _PaymentHistoryTab(
            history: _history,
            loading: _historyLoading,
            error: _historyError,
            onRetry: _loadHistory,
          ),
      };

  /// The bottom bar: **ชำระเงิน** and the contract document, either, both or
  /// neither.
  ///
  /// Both are independently gated — ชำระเงิน on `is_show_payButton`, the
  /// document on [ComcodeConfig.showsContractButton] — so the bar can hold one
  /// button, two, or vanish entirely. The source has the same shape.
  Widget _buildBottomBar(LoanContract contract) {
    final showsDocument = _contractDocumentUrl != null &&
        _comcodeConfig.showsContractButton(
          comcode: contract.barcodeDetails.comcode,
          loanTypeCode: contract.contractDetails.loanTypeCode,
        );
    if (!_showPayButton && !showsDocument) return const SizedBox.shrink();

    final label =
        _comcodeConfig.contractButtonLabel(contract.barcodeDetails.comcode) ??
            'คู่สัญญา';
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(11, 12, 11, 12),
        child: Row(
          children: [
            if (_showPayButton)
              Expanded(
                child: _BottomBarButton(
                  label: 'ชำระเงิน',
                  fill: LoanDetailPalette.contractButtonText,
                  labelColor: Colors.white,
                  onTap: () => _openPayment(contract),
                ),
              ),
            if (_showPayButton && showsDocument) const SizedBox(width: 12),
            if (showsDocument)
              Expanded(
                child: _BottomBarButton(
                  label: label,
                  fill: LoanDetailPalette.contractButtonFill,
                  labelColor: LoanDetailPalette.contractButtonText,
                  onTap: _onContractDocumentPressed,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Opens **ชำระเงิน** for this contract.
  ///
  /// No `fromHost`: the customer came from this screen, so back should return
  /// here rather than close the WebView out from under them.
  ///
  /// The contract goes with it. This screen loaded that row to draw what the
  /// customer is looking at, and the payment screen needs the same one — so
  /// re-fetching it would put a spinner in front of data already in memory.
  /// The query string still names the contract, so a reload re-fetches.
  void _openPayment(LoanContract contract) {
    context.push(
      Uri(
        path: AppRoutes.loanPayment,
        queryParameters: {
          'contNo': contract.contractNo.trim(),
          if (contract.dbName.trim().isNotEmpty)
            'dbName': contract.dbName.trim(),
        },
      ).toString(),
      extra: LoanPaymentSeed(contract: contract),
    );
  }
}

/// One button in the bottom bar. Both are the same shape; only the fill and
/// the label colour differ.
class _BottomBarButton extends StatelessWidget {
  const _BottomBarButton({
    required this.label,
    required this.fill,
    required this.labelColor,
    required this.onTap,
  });

  final String label;
  final Color fill;
  final Color labelColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: const BorderRadius.all(Radius.circular(14)),
          ),
          child: Text(
            label,
            style: GoogleFonts.notoSansThai(
              fontSize: 16,
              height: 1,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
        ),
      );
}

// ── tab bodies ────────────────────────────────────────────────────────

/// **ข้อมูลสินเชื่อ** — the contract's own terms and its collateral.
class _LoanInfoTab extends StatelessWidget {
  const _LoanInfoTab({required this.contract});

  final LoanContract contract;

  @override
  Widget build(BuildContext context) {
    final details = contract.contractDetails;
    final summary = LoanDetailSummary(contract);

    return Column(
      children: [
        LoanDetailFieldRow(
          label: 'ค่างวด',
          value: formatMoney(details.installmentAmount),
          suffix: 'บาท',
        ),
        LoanDetailFieldRow(
          label: 'จำนวนงวด',
          value: '${summary.totalInstallmentNumber}',
          suffix: 'งวด',
        ),
        LoanDetailFieldRow(
          label: 'สาขาที่ทำสัญญา',
          value: '${contract.branchName} (${contract.branchCode})',
        ),
        LoanDetailFieldRow(
          label: 'วันที่ทำสัญญา',
          value: formatThaiDate(contract.contractDate),
        ),
        LoanDetailFieldRow(
            label: 'กลุ่มสินค้า', value: details.loanTypeName.trim()),
        LoanDetailFieldRow(
            label: 'ยี่ห้อสินค้า', value: details.vehicleBrand.trim()),
        LoanDetailFieldRow(label: 'รุ่นสินค้า', value: summary.productModel),
        LoanDetailFieldRow(
          label: 'รายละเอียดสินค้า',
          value: summary.productDetail,
          suffix: summary.productDetailSuffix,
        ),
        LoanDetailFieldRow(
            label: 'เลขทะเบียน', value: details.collateralInformation.trim()),
        // `first_due_date` / `last_due_date` from the contract row. The second
        // falls back to the top-level `contract_close_date`, which is what the
        // source does for a loan that omits it.
        LoanDetailFieldRow(
          label: 'วันเริ่มงวดแรก',
          value: details.firstDueDate.trim().isNotEmpty
              ? formatThaiDate(details.firstDueDate)
              : '-',
        ),
        LoanDetailFieldRow(
          label: 'วันงวดสุดท้าย',
          value: formatThaiDate(details.lastDueDate.trim().isNotEmpty
              ? details.lastDueDate
              : contract.contractCloseDate),
        ),
        _dataDateFooter(contract),
      ],
    );
  }
}

/// **ข้อมูลการชำระ** — what has been paid and what is behind.
class _PaymentInfoTab extends StatelessWidget {
  const _PaymentInfoTab({required this.contract});

  final LoanContract contract;

  @override
  Widget build(BuildContext context) {
    final payment = contract.paymentDetails;
    return Column(
      children: [
        LoanDetailFieldRow(
          label: 'ชำระค่างวดแล้ว',
          value: formatMoney(payment.totalPaidAmount),
          suffix: 'บาท',
        ),
        LoanDetailFieldRow(
          label: 'จำนวนวันที่ค้าง',
          value: '${payment.overdueDays}',
          suffix: 'วัน',
        ),
        LoanDetailFieldRow(
          label: 'จำนวนงวดที่ค้าง',
          value: '${payment.overdueTerms}',
          suffix: 'งวด',
        ),
        LoanDetailFieldRow(
          label: 'วันชำระครั้งล่าสุด',
          value: formatThaiDate(payment.latestPaidDate),
        ),
        _dataDateFooter(contract),
      ],
    );
  }
}

/// **ประวัติการชำระ** — `POST /payment/history_new`, loaded on first open.
class _PaymentHistoryTab extends StatelessWidget {
  const _PaymentHistoryTab({
    required this.history,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final PaymentHistory? history;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(
            color: Color.fromRGBO(219, 119, 26, 1),
          ),
        ),
      );
    }
    final message = error;
    if (message != null) {
      // ⚠ The source renders an empty `Container()` on this branch, so a failed
      // history load is indistinguishable from a contract with no payments.
      // Deliberately not reproduced — a retry is what the customer needs, and
      // this repo's other screens all offer one.
      return SizedBox(
        height: 240,
        child: PLoanErrorView(message: message, onRetry: onRetry),
      );
    }
    final loaded = history;
    if (loaded == null || loaded.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'ไม่มีประวัติการชำระ',
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansThai(fontSize: 18),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final entry in loaded.entries)
          PaymentHistoryCard(
            headingDate: formatThaiShortDate(entry.paidOn),
            paidAtLabel: [
              formatThaiShortDate(entry.paidOn),
              if (entry.paidAtTime.isNotEmpty) '${entry.paidAtTime} น.',
            ].join(' '),
            amount: '${formatMoney(entry.paidAmount)} บาท',
            channel: entry.paymentChannelName,
          ),
        const SizedBox(height: 24),
        // This tab's own `data_date`, from the history response — not the
        // contract's, which is what the two tabs above quote. They are
        // separate reads taken at different moments, and dating the payment
        // list by when the *contract* was fetched would be wrong. Withheld
        // entirely when the response carries none, rather than shown with a
        // blank date in it.
        if (loaded.dataDate.isNotEmpty)
          LoanDetailDataDateFooter(
            date: formatThaiDate(loaded.dataDate),
            time: formatLoanDetailTime(loaded.dataDate),
          ),
      ],
    );
  }
}

/// `ข้อมูลวันที่ … เวลา … น.` — the same footer closes both data tabs.
Widget _dataDateFooter(LoanContract contract) => LoanDetailDataDateFooter(
      date: formatThaiDate(contract.dataDate),
      time: formatLoanDetailTime(contract.dataDate),
    );
