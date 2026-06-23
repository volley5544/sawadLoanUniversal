import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'components/loan_register_styles.dart';
import 'models/loan_register_form.dart';

/// ยืนยันตัวตน — NDID identity-verification waiting screen (screen #5 on
/// slide 8) followed by the ยืนยันตัวตนสำเร็จ success screen (final frame).
///
/// In the real flow the customer is handed off to their bank's app (K+ PIN
/// pad / NDID consent — third-party screens not part of this build) and the IDP
/// calls back with the result. Here that hop is simulated: a countdown timer
/// runs while waiting, and confirming pops `true` back through the NDID flow.
class NdidVerifyPage extends StatefulWidget {
  const NdidVerifyPage({Key? key, this.form}) : super(key: key);

  final LoanRegisterForm? form;

  @override
  State<NdidVerifyPage> createState() => _NdidVerifyPageState();
}

class _NdidVerifyPageState extends State<NdidVerifyPage> {
  /// Countdown for the customer to complete verification in their bank app.
  Duration _remaining = const Duration(hours: 1);
  Timer? _timer;

  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remaining.inSeconds <= 0) {
        t.cancel();
        return;
      }
      setState(() => _remaining -= const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formattedTime {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(_remaining.inHours)}:${two(_remaining.inMinutes % 60)}:${two(_remaining.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: LoanRegisterStyles.primary),
        centerTitle: true,
        title: Text(_verified ? 'ผลการยืนยันตัวตน' : 'ยืนยันตัวตน',
            style: LoanRegisterStyles.appBarTitleStyle()),
      ),
      body: _verified ? _successBody() : _waitingBody(),
    );
  }

  // ── Waiting (countdown) ────────────────────────────────────────────
  Widget _waitingBody() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
                horizontal: LoanRegisterStyles.padding, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.verified_user_outlined,
                    size: 64, color: LoanRegisterStyles.primary),
                const SizedBox(height: 16),
                Text(
                  'ยืนยันตัวตน',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: LoanRegisterStyles.value,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'ทำรายการยืนยันตัวตนผ่านแอปพลิเคชันของธนาคารที่เลือก '
                  'ภายในระยะเวลาที่กำหนด (จำกัด 1 ครั้ง/รายการ) '
                  'กรุณาเปิดแอปธนาคารเพื่อยืนยันตัวตนของท่าน',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 13,
                    height: 1.5,
                    color: LoanRegisterStyles.label,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Transaction Ref: 1234ETE',
                  style: LoanRegisterStyles.labelStyle(),
                ),
                const SizedBox(height: 24),
                Text(
                  _formattedTime,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: LoanRegisterStyles.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text('เวลาคงเหลือ', style: LoanRegisterStyles.labelStyle()),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(LoanRegisterStyles.padding, 4,
                LoanRegisterStyles.padding, 12),
            child: Column(
              children: [
                // Simulates the IDP callback (the real result arrives from the
                // bank app). Drives the UI-only flow to the success state.
                _Button(
                  label: 'จำลองยืนยันตัวตนสำเร็จ',
                  filled: true,
                  onTap: () => setState(() {
                    _verified = true;
                    _timer?.cancel();
                  }),
                ),
                const SizedBox(height: 10),
                _Button(
                  label: 'ยกเลิก',
                  filled: false,
                  onTap: () => context.pop(false),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Success ────────────────────────────────────────────────────────
  Widget _successBody() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: LoanRegisterStyles.primary, width: 3),
                  ),
                  child: Icon(Icons.check,
                      size: 56, color: LoanRegisterStyles.primary),
                ),
                const SizedBox(height: 20),
                Text(
                  'ยืนยันตัวตนสำเร็จ',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: LoanRegisterStyles.value,
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(LoanRegisterStyles.padding, 4,
                LoanRegisterStyles.padding, 12),
            child: _Button(
              label: 'ตกลง',
              filled: true,
              onTap: () => context.pop(true),
            ),
          ),
        ),
      ],
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled
              ? LoanRegisterStyles.primary
              : LoanRegisterStyles.primarySoft,
          borderRadius: BorderRadius.circular(14),
          border: filled
              ? null
              : Border.all(color: LoanRegisterStyles.primary),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansThai(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: filled ? Colors.white : LoanRegisterStyles.primary,
          ),
        ),
      ),
    );
  }
}
