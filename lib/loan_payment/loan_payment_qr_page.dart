/// **ชำระด้วย QR** — the instalment bill, as a scannable code.
///
/// Ported from LandAndHouseWeb's `customer_payment/customer_qr_payment_page`.
/// Nothing is filed here and nothing is polled: the screen's whole job is to
/// render a barcode the customer pays at their bank. This app never sees that
/// transaction.
///
/// ## Why this is a separate page from the top-up flow's QR screen
///
/// The two are close but not the same, and the differences are not cosmetic:
/// this one labels its figure `จำนวนเงินค่างวด` (an instalment, where the
/// top-up one bills accrued interest), carries the 30-minute settlement note,
/// and has **no ปรับปรุงยอดชำระ button** — because it has nothing to go back
/// and re-price. That button on the top-up screen is half of a live hand-back
/// relationship with its amount screen, which reloads `/topup/detail` on
/// return; wiring a flag through to suppress it would couple a pentested,
/// shipped payment screen to a new one for no gain.
///
/// What the two **do** share is the part that was hard: capturing the
/// boundary and saving it, in `services/qr_image_capture.dart`. Sharing the
/// logic and separating the layout is the split that matches where they
/// actually differ.
library;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_state.dart';
import '../loan_detail/components/loan_detail_components.dart';
import '../loan_register/components/loan_register_styles.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../p_loan/application/models/loan_contract.dart';
import '../router/app_router.dart';
import '../services/p_loan_api.dart';
import '../services/qr_image_capture.dart';
import '../services/srisawad_api.dart';

class LoanPaymentQrPage extends StatefulWidget {
  const LoanPaymentQrPage({
    super.key,
    required this.contractNo,
    required this.amount,
    this.dbName = '',
  });

  final String contractNo;
  final String dbName;

  /// The figure the payment screen settled on. Carried in the query string, so
  /// a reload reproduces the same bill rather than a blank one — and so the
  /// amount on screen is provably the amount that was chosen, not something
  /// re-derived here from data that may have moved.
  final double amount;

  @override
  State<LoanPaymentQrPage> createState() => _LoanPaymentQrPageState();
}

class _LoanPaymentQrPageState extends State<LoanPaymentQrPage> {
  final GlobalKey _captureKey = GlobalKey();

  LoanContract? _contract;
  String? _error;
  bool _saving = false;

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
    try {
      final contracts = await PLoanApi.listContracts(
        hashThaiId: appState.hashThaiId,
        token: appState.authToken,
      );
      final wanted = widget.contractNo.trim();
      final db = widget.dbName.trim();
      LoanContract? match;
      for (final contract in contracts) {
        if (contract.contractNo.trim() != wanted) continue;
        if (db.isNotEmpty && contract.dbName.trim() != db) continue;
        match = contract;
        break;
      }
      if (!mounted) return;
      if (match == null) {
        setState(() => _error = 'ไม่พบสัญญาเลขที่ $wanted');
        return;
      }
      setState(() => _contract = match);
    } on SrisawadApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// The Thai bill-payment barcode payload.
  ///
  /// ⚠ **Byte-for-byte the source's `genQRCodePayment`, including the amount's
  /// trailing `.0`** — it multiplies by 100 and calls `toString()` on a
  /// `double`, so ฿1,234 renders as `123400.0` rather than the integer satang
  /// the barcode standard describes. Reproduced rather than "fixed": this
  /// string is what the shipped app prints and what the bank's scanner is
  /// known to accept, and changing a live payment reference on a hunch is not
  /// a change to make from here. Same note as the top-up QR screen; confirm
  /// the intended format with the payments team before touching either.
  String get _payload {
    final barcode = _contract?.barcodeDetails;
    final satang = (widget.amount * 100).toString();
    return '|${barcode?.taxId ?? ''}${barcode?.suffix ?? ''}\n'
        '${barcode?.ref1 ?? ''}\n'
        '${barcode?.ref2 ?? ''}\n'
        '$satang\n';
  }

  String _plate(LoanContract contract) {
    final car = contract.carDetails;
    final joined = '${car.registrationPrefix} ${car.registration}'.trim();
    return joined.isNotEmpty
        ? joined
        : contract.contractDetails.collateralInformation;
  }

  Future<void> _saveImage() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final ratio = qrCapturePixelRatio(context);
    final message = await captureAndSaveQrImage(
      boundaryKey: _captureKey,
      pixelRatio: ratio,
      galleryName: 'QR-installment_${DateTime.now().millisecondsSinceEpoch}',
      downloadFileName: 'qr-installment.png',
      diagnosticsLabel: 'loan payment qr',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: loanDetailAppBar(
        context,
        'ชำระด้วย QR',
        onBack: () =>
            context.canPop() ? context.pop() : context.go(AppRoutes.home),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final error = _error;
    if (error != null) return PLoanErrorView(message: error, onRetry: _load);
    final contract = _contract;
    if (contract == null) {
      return const PLoanLoadingView(message: 'กำลังสร้างคิวอาร์โค้ด...');
    }

    // ⚠ A scroll view with an explicit child, **not** a `ListView`: the saved
    // image is the boundary's whole subtree, and a lazy sliver never builds
    // what is off-screen, so the capture would be cropped to wherever the
    // customer had scrolled. Same constraint as the top-up QR screen.
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8, bottom: 30),
      child: Column(
        // `Column` centres where `ListView` stretches — without this the
        // captions and the divider shrink to their own width.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RepaintBoundary(
            key: _captureKey,
            // The boundary paints only its own subtree, so without an opaque
            // fill the saved PNG is transparent where the Scaffold's white
            // shows through — which reads as black in most gallery viewers.
            child: ColoredBox(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _captureContent(contract),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: _QrSaveButton(
              busy: _saving,
              onTap: _saving ? null : _saveImage,
            ),
          ),
        ],
      ),
    );
  }

  /// Everything บันทึกรูปภาพ captures: the contract card down to the
  /// settlement note, i.e. the whole screen **except** the app bar and the
  /// button.
  List<Widget> _captureContent(LoanContract contract) => [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: LoanRegisterStyles.padding),
          child: ContractSummaryCard(
            loanTypeCode: contract.contractDetails.loanTypeCode,
            loanTypeName: contract.contractDetails.loanTypeName,
            contractNo: contract.contractNo,
            collateralInformation:
                contract.contractDetails.collateralInformation,
          ),
        ),
        SizedBox(
          height: 80,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StackedValue(label: 'เลขทะเบียน', value: _plate(contract)),
              // The source's label, and the right one here: this bill *is* an
              // instalment, unlike the top-up screen's, which bills accrued
              // interest and says ยอดที่ต้องชำระ instead.
              _StackedValue(
                label: 'จำนวนเงินค่างวด',
                value: formatMoney(widget.amount),
              ),
            ],
          ),
        ),
        const Divider(thickness: 2, color: _QrPalette.divider),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          child: Text(
            '*กรุณาชำระเงินภายในวัน 00:05 ถึง 22:45 เท่านั้น\n'
            'เพื่อหลีกเลี่ยงการเสียดอกเบี้ยเพิ่มเติม',
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansThai(
              fontSize: 12,
              height: 1.4,
              color: _QrPalette.error,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Container(
            width: 200,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _QrPalette.navy,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              'คิวอาร์โค้ด',
              style:
                  GoogleFonts.notoSansThai(fontSize: 14, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: SizedBox(
            width: 250,
            height: 250,
            child: Center(
              child: BarcodeWidget(
                barcode: Barcode.qrCode(),
                data: _payload,
                width: 200,
                height: 200,
                color: Colors.black,
                backgroundColor: Colors.transparent,
                drawText: true,
                errorBuilder: (_, _) => const SizedBox(width: 200, height: 200),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _Caption('R1 : ${contract.barcodeDetails.ref1}'),
        const SizedBox(height: 10),
        _Caption('R2 : ${contract.barcodeDetails.ref2}'),
        const SizedBox(height: 10),
        const _Caption('สามารถสแกนชำระค่างวด ผ่านโมบายแอปได้ทุกธนาคาร'),
        const _Caption('ยกเว้นธนาคาร ธ.ก.ส. และ ออมสิน'),
        const SizedBox(height: 10),
        // This build never sees the bank transaction, so the customer has to
        // be told when to expect their balance to move rather than watching
        // for it here.
        const _Caption('หลังชำระสำเร็จยอดบัญชีจะถูกปรับภายใน 30 นาที'),
      ];
}

/// A label above its value, both centred — the plate/amount row.
class _StackedValue extends StatelessWidget {
  const _StackedValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text(
            label,
            style: GoogleFonts.notoSansThai(
                fontSize: 16, color: _QrPalette.caption),
          ),
          Text(
            value,
            style: GoogleFonts.notoSansThai(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _QrPalette.navy,
            ),
          ),
        ],
      );
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style:
            GoogleFonts.notoSansThai(fontSize: 12, color: _QrPalette.caption),
      );
}

class _QrSaveButton extends StatelessWidget {
  const _QrSaveButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 140,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _QrPalette.orange,
            borderRadius: BorderRadius.circular(12),
          ),
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  'บันทึกรูปภาพ',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      );
}

/// The source theme's own colours, as on the top-up QR screen — see the class
/// doc there for why these pages quote them rather than using
/// [LoanRegisterStyles]. Duplicated rather than shared so that restyling one
/// payment screen cannot silently restyle the other.
abstract final class _QrPalette {
  static const Color navy = Color(0xFF003063);
  static const Color caption = Color(0xFF646464);
  static const Color divider = Color(0xFFE0E3E7);
  static const Color error = Color(0xFFFF0000);
  static const Color orange = Color(0xFFDB771A);
}
