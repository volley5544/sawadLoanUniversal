import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../loan_register/components/loan_register_styles.dart';
import '../../loan_register/components/register_step_indicator.dart';
import '../../models/customer_address.dart';
import '../../router/app_router.dart';
import '../../services/p_loan_api.dart';
import '../../services/user_api.dart';
import 'components/p_loan_components.dart';
import 'models/p_loan_flow.dart';

/// **Step 5 — ตรวจสอบข้อมูลส่วนตัว.** Read-only review of the payout account,
/// phone number and the four registered addresses, then a confirmation sheet.
///
/// The source's confirm sheet navigated to step 6 from inside itself, which
/// left the calling screen with no say in the flow. Here the sheet returns a
/// bool and this page does the navigating.
class PLoanCustomerDataPage extends StatefulWidget {
  const PLoanCustomerDataPage({super.key, required this.flow});

  final PLoanFlow flow;

  @override
  State<PLoanCustomerDataPage> createState() => _PLoanCustomerDataPageState();
}

class _PLoanCustomerDataPageState extends State<PLoanCustomerDataPage> {
  CustomerAddressBook? _addresses;
  String? _error;
  bool _loading = true;

  PLoanFlow get _flow => widget.flow;

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
      final book = await PLoanApi.fetchAddressBook(
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

  /// Bank-account confirmation sheet. Returns true when the customer confirms.
  Future<void> _confirm() async {
    final contract = _flow.contract;
    if (contract == null) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x99000000),
      isScrollControlled: true,
      builder: (context) => _ConfirmAccountSheet(
        bankCode: contract.contractBankBrandname,
        accountNo: contract.contractBankAccount,
        logoBase64: contract.branchImage,
      ),
    );
    if (confirmed == true && mounted) {
      context.push(AppRoutes.pLoanConclusion, extra: _flow);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: pLoanAppBar(context, 'ตรวจสอบข้อมูลส่วนตัว'),
      body: Column(
        children: [
          const PLoanMockBanner(),
          PLoanKindBanner(kind: _flow.kind),
          const RegisterStepIndicator(currentStep: 5, totalSteps: 6),
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

    final contract = _flow.contract!;
    final customer = _flow.customer;
    final book = _addresses!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(LoanRegisterStyles.padding, 4,
          LoanRegisterStyles.padding, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'กรุณาตรวจสอบความถูกต้องของข้อมูลอีกครั้งเพื่อยืนยันการขอสินเชื่อ',
            style: GoogleFonts.notoSansThai(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: LoanRegisterStyles.value,
              height: 1.5,
            ),
          ),
          const PLoanSectionHeader('ข้อมูลเลขที่บัญชี'),
          Text('เลขที่บัญชี',
              style: GoogleFonts.notoSansThai(
                  fontSize: 13, color: LoanRegisterStyles.label)),
          const SizedBox(height: 8),
          BankAccountCard(
            bankCode: contract.contractBankBrandname,
            accountNo: contract.contractBankAccount,
            logoBytes: decodeBase64Image(contract.branchImage),
          ),
          const PLoanSectionHeader('ข้อมูลโทรศัพท์'),
          PLoanAmountRow(
            label: 'เบอร์โทรศัพท์',
            value: customer?.phoneNumber ?? '',
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
  });

  final String bankCode;
  final String accountNo;
  final String logoBase64;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 3,
              color: LoanRegisterStyles.label,
            ),
            const SizedBox(height: 16),
            Text('ยืนยันข้อมูล',
                style: LoanRegisterStyles.appBarTitleStyle()
                    .copyWith(fontSize: 20)),
            const SizedBox(height: 8),
            Text(
              'คุณยืนยันที่จะให้ทางเราโอนเงินไปยังเลขที่บัญชีนี้ใช่หรือไม่?',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansThai(
                fontSize: 14,
                color: LoanRegisterStyles.label,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            BankAccountCard(
              bankCode: bankCode,
              accountNo: accountNo,
              logoBytes: decodeBase64Image(logoBase64),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: LoanRegisterStyles.primarySoft,
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
                    height: 56,
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

/// Shown when the customer says their details are wrong.
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
