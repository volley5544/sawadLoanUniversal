import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../router/app_router.dart';
import '../services/native_bridge.dart';
import 'components/loan_register_styles.dart';

/// Loan-register entry/category page (รายการ) reached from the
/// "สมัครสินเชื่อ" home menu. Lets the customer pick what they want to register
/// for (มอเตอร์ไซต์) or resume a draft (รายการเตรียมข้อมูล). Selecting the
/// product card — or tapping ถัดไป — opens step 1 of the wizard.
class LoanRegisterListPage extends StatefulWidget {
  const LoanRegisterListPage({Key? key}) : super(key: key);

  @override
  State<LoanRegisterListPage> createState() => _LoanRegisterListPageState();
}

enum _RegisterCategory { motorcycle, draft }

class _LoanRegisterListPageState extends State<LoanRegisterListPage> {
  _RegisterCategory _selected = _RegisterCategory.motorcycle;

  void _goToStep1() {
    // No form passed -> CustomerInfoPage seeds step 1 from AppState().customerDetail.
    context.push(AppRoutes.customerInfo);
  }

  /// Back from the list page (the root of the web flow). If there's web history
  /// to pop, pop it; otherwise ask the native WebView host to close its page
  /// (the host runs `Navigator.of(context).pop()`). No-op in a plain browser.
  void _onBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      NativeCameraBridge.closeWebview();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanRegisterStyles.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(
          color: LoanRegisterStyles.primary,
          onPressed: _onBack,
        ),
        centerTitle: true,
        title: Text(
          'รายการ',
          style: LoanRegisterStyles.appBarTitleStyle()
              .copyWith(color: LoanRegisterStyles.primary),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
            LoanRegisterStyles.padding, 20, LoanRegisterStyles.padding, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _CategoryCard(
                assetName: 'MotorLoanIcon.svg',
                label: 'มอเตอร์ไซต์',
                selected: _selected == _RegisterCategory.motorcycle,
                onTap: () {
                  setState(() => _selected = _RegisterCategory.motorcycle);
                  _goToStep1();
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _CategoryCard(
                assetName: 'DocumentIcon.svg',
                label: 'รายการเตรียมข้อมูล',
                selected: _selected == _RegisterCategory.draft,
                onTap: () {
                  setState(() => _selected = _RegisterCategory.draft);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('รายการเตรียมข้อมูล')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              LoanRegisterStyles.padding, 8, LoanRegisterStyles.padding, 12),
          child: GestureDetector(
            onTap: _goToStep1,
            child: Container(
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: LoanRegisterStyles.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'ถัดไป',
                style: GoogleFonts.notoSansThai(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.assetName,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String assetName;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? LoanRegisterStyles.primary
                : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.08),
              offset: Offset(0, 3),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/$assetName',
              width: 44,
              height: 44,
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansThai(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? LoanRegisterStyles.value
                      : LoanRegisterStyles.value,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
