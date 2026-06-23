import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../router/app_router.dart';
import 'components/loan_register_styles.dart';

/// เลือกธนาคารที่เกี่ยวข้อง NDID — pick the Identity Provider (IDP) bank used
/// for NDID verification (screens #3–#4 on slide 8).
///
/// Shows banks the customer has already registered with NDID, and those they
/// have not. Picking a registered bank and tapping ถัดไป continues to
/// [NdidVerifyPage]. (The bank's own app — K+ PIN pad, NDID consent — is a
/// third-party screen handled outside this build.)
class NdidBankSelectPage extends StatefulWidget {
  const NdidBankSelectPage({Key? key}) : super(key: key);

  @override
  State<NdidBankSelectPage> createState() => _NdidBankSelectPageState();
}

class _NdidBank {
  const _NdidBank(this.code, this.name, this.color);
  final String code;
  final String name;
  final Color color;
}

class _NdidBankSelectPageState extends State<NdidBankSelectPage> {
  String? _selected;

  // Banks the customer has registered with NDID (UI-only).
  static const List<_NdidBank> _registered = [
    _NdidBank('BBL', 'ธนาคารกรุงเทพ', Color(0xFF1B3A8B)),
    _NdidBank('KRUNGSRI', 'ธนาคารกรุงศรี', Color(0xFFFCC200)),
    _NdidBank('K+', 'ธนาคารกสิกรไทย', Color(0xFF138F2D)),
  ];

  // Banks not yet registered with NDID (must register first).
  static const List<_NdidBank> _notRegistered = [
    _NdidBank('SCB', 'ธนาคารไทยพาณิชย์', Color(0xFF4E2A84)),
    _NdidBank('KTB', 'ธนาคารกรุงไทย', Color(0xFF00A4E4)),
    _NdidBank('TTB', 'ทีทีบี', Color(0xFF0050A0)),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: LoanRegisterStyles.primary),
        centerTitle: true,
        title: Text('เลือกผู้ให้บริการยืนยันตัวตน NDID',
            style: LoanRegisterStyles.appBarTitleStyle().copyWith(fontSize: 15)),
      ),
      body: Column(
        children: [
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: LoanRegisterStyles.padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _groupTitle('ผู้ให้บริการที่เคยลงทะเบียน NDID'),
                  _bankGrid(_registered, enabled: true),
                  const SizedBox(height: 20),
                  _groupTitle('ผู้ให้บริการที่ยังไม่ลงทะเบียน NDID'),
                  _bankGrid(_notRegistered, enabled: false),
                  const SizedBox(height: 8),
                  Text(
                    'หากยังไม่ได้ลงทะเบียน NDID กรุณาลงทะเบียนกับธนาคารก่อน',
                    style: LoanRegisterStyles.labelStyle(),
                  ),
                ],
              ),
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _groupTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      child: Text(
        text,
        style: GoogleFonts.notoSansThai(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: LoanRegisterStyles.value,
        ),
      ),
    );
  }

  Widget _bankGrid(List<_NdidBank> banks, {required bool enabled}) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: banks
          .map((b) => _bankTile(b, enabled: enabled))
          .toList(growable: false),
    );
  }

  Widget _bankTile(_NdidBank bank, {required bool enabled}) {
    final bool isSelected = enabled && _selected == bank.code;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: enabled ? () => setState(() => _selected = bank.code) : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 96,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? LoanRegisterStyles.primary
                  : LoanRegisterStyles.cardBorder,
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bank.color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  bank.code,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                bank.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: GoogleFonts.notoSansThai(
                  fontSize: 11,
                  color: LoanRegisterStyles.value,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(LoanRegisterStyles.padding, 4,
            LoanRegisterStyles.padding, 12),
        child: Row(
          children: [
            Expanded(
              child: _BarButton(
                label: 'ย้อนกลับ',
                filled: false,
                onTap: () => context.pop(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BarButton(
                label: 'ถัดไป',
                filled: true,
                enabled: _selected != null,
                onTap: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _next() async {
    if (_selected == null) return;
    final ok = await context.push<bool>(AppRoutes.ndidVerify);
    if (ok == true && mounted) context.pop(true);
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.filled,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Color primary = LoanRegisterStyles.primary;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled
              ? (enabled ? primary : primary.withOpacity(0.4))
              : LoanRegisterStyles.primarySoft,
          borderRadius: BorderRadius.circular(14),
          border: filled ? null : Border.all(color: primary),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansThai(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: filled ? Colors.white : primary,
          ),
        ),
      ),
    );
  }
}
