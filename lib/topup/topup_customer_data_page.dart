import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../loan_register/components/loan_register_styles.dart';
import '../models/customer_address.dart';
import '../p_loan/application/components/p_loan_components.dart';
import '../router/app_router.dart';
import '../services/topup_api.dart';
import '../services/user_api.dart';
import 'components/topup_components.dart';
import 'models/topup_flow.dart';

/// **Step 6 — ตรวจสอบข้อมูลส่วนตัว.** Review of the name, payout account,
/// phone number and the four registered addresses, then a confirmation sheet.
///
/// Everything here is read-only. A top-up pays into the account already
/// registered against the contract it replaces, and the name, phone and
/// addresses are the customer's own record — "ไม่ถูกต้อง" points at the branch,
/// which is what can actually change them.
///
/// The source's confirm sheet navigated onward from inside itself, which left
/// the calling screen with no say in the flow. Here the sheet returns a bool
/// and this page does the navigating.
class TopupCustomerDataPage extends StatefulWidget {
  const TopupCustomerDataPage({super.key, required this.flow});

  final TopupFlow flow;

  @override
  State<TopupCustomerDataPage> createState() => _TopupCustomerDataPageState();
}

class _TopupCustomerDataPageState extends State<TopupCustomerDataPage> {
  CustomerAddressBook? _addresses;
  String? _error;
  bool _loading = true;

  TopupFlow get _flow => widget.flow;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final book = await TopupApi.fetchAddressBook(
        hashThaiId: _flow.hashThaiId,
        token: _flow.authToken,
      );
      if (!mounted) return;
      _flow.addressBook = book;
      setState(() {
        _addresses = book;
        _loading = false;
      });
    } on UserApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  /// Payout-account confirmation sheet. Returns true when the customer
  /// confirms, and only then does this page advance.
  Future<void> _confirm() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x99000000),
      isScrollControlled: true,
      builder: (context) => _ConfirmAccountSheet(
        bankCode: _flow.bankCode,
        accountNo: _flow.bankAccountNo,
        logoBase64: _flow.bankLogoBase64,
        payoutAmount: _flow.payoutAmount,
      ),
    );
    if (confirmed == true && mounted) {
      context.push(AppRoutes.topupConclusion, extra: _flow);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: topupAppBar(context, 'ตรวจสอบข้อมูลส่วนตัว'),
      body: Column(
        children: [
          const PLoanMockBanner(),
          const TopupStepIndicator(5),
          Expanded(child: _body()),
        ],
      ),
      bottomNavigationBar: _loading || _error != null ? null : _bottomBar(),
    );
  }

  Widget _body() {
    final error = _error;
    if (error != null) return PLoanErrorView(message: error, onRetry: _load);
    if (_loading) {
      return const PLoanLoadingView(message: 'กำลังโหลดข้อมูลที่อยู่...');
    }

    final customer = _flow.customer;
    final book = _addresses!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          LoanRegisterStyles.padding, 4, LoanRegisterStyles.padding, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'กรุณาตรวจสอบความถูกต้องของข้อมูลอีกครั้งเพื่อยืนยันการขอสินเชื่อเพิ่ม',
            style: GoogleFonts.notoSansThai(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: LoanRegisterStyles.value,
              height: 1.5,
            ),
          ),
          const PLoanSectionHeader('ข้อมูลเลขที่บัญชี'),
          Text('บัญชีรับเงินสินเชื่อ',
              style: GoogleFonts.notoSansThai(
                  fontSize: 13, color: LoanRegisterStyles.label)),
          const SizedBox(height: 8),
          BankAccountCard(
            bankCode: _flow.bankCode,
            accountNo: _flow.bankAccountNo,
            logoBytes: decodeBase64Image(_flow.bankLogoBase64),
          ),
          const PLoanSectionHeader('ข้อมูลส่วนตัว'),
          PLoanAmountRow(
            label: 'ชื่อ-สกุล',
            // firstName + lastName, matching the label — the คำนำหน้า is
            // deliberately left out.
            value: customer?.fullName ?? '',
            showDivider: false,
          ),
          const PLoanSectionHeader('ข้อมูลโทรศัพท์'),
          PLoanAmountRow(
            label: 'เบอร์โทรศัพท์',
            // Grouped ###-###-#### for reading; the payload keeps raw digits.
            value: formatPhone(customer?.phoneNumber),
            showDivider: false,
          ),
          const PLoanSectionHeader('ข้อมูลที่อยู่'),
          _addressCard('assets/p_loan/current-address-icon.svg',
              'ที่อยู่ปัจจุบัน', book.currentAddress),
          _addressCard('assets/p_loan/registered-address.svg',
              'ที่อยู่ตามทะเบียนบ้าน', book.registrationAddress),
          _addressCard('assets/p_loan/card-id-address.svg',
              'ที่อยู่ตามบัตรประชาชน', book.idCardAddress),
          _addressCard('assets/p_loan/office-address.svg',
              'ที่ทำงาน/ที่อยู่อื่นๆ', book.otherAddress),
        ],
      ),
    );
  }

  /// One address row. An empty block renders a dash rather than the literal
  /// `"null"` the source printed.
  Widget _addressCard(String iconAsset, String title, AddressInfo address) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: LoanRegisterStyles.cardBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SvgPicture.asset(iconAsset, width: 36, height: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: LoanRegisterStyles.value,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address.isEmpty ? '-' : address.oneLine,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 13,
                      color: LoanRegisterStyles.label,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: LoanRegisterStyles.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 56,
              child: OutlinedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const _ContactBranchSheet(),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: LoanRegisterStyles.primarySoft,
                  side: BorderSide(color: LoanRegisterStyles.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'ไม่ถูกต้อง',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: LoanRegisterStyles.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: LoanRegisterStyles.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'ยืนยัน',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Transfer to this account?" sheet. Pops `true` on confirm so the caller
/// decides what happens next.
class _ConfirmAccountSheet extends StatelessWidget {
  const _ConfirmAccountSheet({
    required this.bankCode,
    required this.accountNo,
    required this.logoBase64,
    required this.payoutAmount,
  });

  final String bankCode;
  final String accountNo;
  final String logoBase64;
  final int payoutAmount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ยืนยันข้อมูล',
                style: LoanRegisterStyles.appBarTitleStyle()
                    .copyWith(fontSize: 18)),
            const SizedBox(height: 14),
            BankAccountCard(
              bankCode: bankCode,
              accountNo: accountNo,
              logoBytes: decodeBase64Image(logoBase64),
            ),
            const SizedBox(height: 14),
            PLoanAmountRow(
              label: 'ยอดโอนเงินเข้าบัญชี',
              value: '${formatMoney(payoutAmount)} บาท',
              emphasis: true,
              showDivider: false,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: LoanRegisterStyles.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'ตรวจสอบอีกครั้ง',
                        style: GoogleFonts.notoSansThai(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: LoanRegisterStyles.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LoanRegisterStyles.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'ยืนยัน',
                        style: GoogleFonts.notoSansThai(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the customer says their own record is wrong — the branch is what
/// can change it, so this points them there rather than offering an edit the
/// flow cannot honour.
class _ContactBranchSheet extends StatelessWidget {
  const _ContactBranchSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.support_agent,
                size: 48, color: LoanRegisterStyles.primary),
            const SizedBox(height: 12),
            Text('ติดต่อสาขา',
                style: LoanRegisterStyles.appBarTitleStyle()
                    .copyWith(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              'กรุณาติดต่อสาขาเจ้าของบัญชีหรือสาขาใกล้บ้าน '
              'หรือโทร 1652 เพื่อแก้ไขข้อมูลส่วนตัว',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansThai(
                fontSize: 14,
                color: LoanRegisterStyles.label,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: LoanRegisterStyles.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'ตกลง',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
