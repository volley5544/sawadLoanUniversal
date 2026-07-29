/// Shared presentation pieces for the P-Loan application flow.
///
/// The source app re-declared these inline on every screen (and re-implemented
/// the money/date formatters as FlutterFlow "custom functions"). They're
/// gathered here so the six screens stay readable, and they build on
/// [LoanRegisterStyles] so the flow matches the rest of the app rather than
/// carrying FlutterFlow's theme across.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../loan_register/components/env_version_tag.dart';
import '../../../loan_register/components/loan_register_styles.dart';
import '../../../services/p_loan_api.dart';
import '../models/p_loan_flow.dart';

// ── formatting ────────────────────────────────────────────────────────

/// `1234567.5` → `'1,234,567.50'`. Mirrors the source's
/// `returnNumberWithComma2Decimal`, including its `'0.00'` fallback for
/// unparseable input.
String formatMoney(num? value) {
  final amount = value ?? 0;
  if (amount.isNaN || amount.isInfinite) return '0.00';
  final negative = amount < 0;
  final parts = amount.abs().toStringAsFixed(2).split('.');
  return '${negative ? '-' : ''}${_groupThousands(parts[0])}.${parts[1]}';
}

/// Whole-baht variant of [formatMoney] (`'1,234,567'`).
String formatWholeMoney(num? value) {
  final amount = (value ?? 0).round();
  final negative = amount < 0;
  return '${negative ? '-' : ''}${_groupThousands(amount.abs().toString())}';
}

String _groupThousands(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Parses an API date and renders it Buddhist-era as `dd/MM/yyyy`. Returns
/// `''` for empty/unparseable values (the source printed the literal `'null'`
/// in that case).
String formatThaiDate(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty || text == 'null') return '';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return '';
  final day = parsed.day.toString().padLeft(2, '0');
  final month = parsed.month.toString().padLeft(2, '0');
  // Years past 2200 are already B.E. (same rule as the wizard's formatter).
  final year = parsed.year > 2200 ? parsed.year : parsed.year + 543;
  return '$day/$month/$year';
}

/// Strips the thousands separators a user may have typed or pasted.
int parseAmount(String text) =>
    int.tryParse(text.replaceAll(',', '').trim()) ?? 0;

/// Rounds down to the nearest 100 — the API only accepts whole-hundred loan
/// amounts, and the source applied this on every amount-field blur.
int roundDownToHundred(int amount) => amount - (amount % 100);

/// Maps the API's short bank codes to Thai display names, passing anything
/// unrecognised through unchanged.
String bankDisplayName(String code) => switch (code.trim().toUpperCase()) {
      'KBANK' => 'ธนาคารกสิกรไทย',
      'SCB' => 'ธนาคารไทยพาณิชย์',
      'BBL' => 'ธนาคารกรุงเทพ',
      'KTB' => 'ธนาคารกรุงไทย',
      'BAY' => 'ธนาคารกรุงศรีอยุธยา',
      'TMB' || 'TTB' => 'ธนาคารทหารไทยธนชาต',
      'GSB' => 'ธนาคารออมสิน',
      'BAAC' => 'ธนาคารเพื่อการเกษตรและสหกรณ์การเกษตร',
      'LHB' => 'ธนาคารแลนด์ แอนด์ เฮ้าส์',
      'CIMB' => 'ธนาคารซีไอเอ็มบีไทย',
      'UOB' => 'ธนาคารยูโอบี',
      'GHB' => 'ธนาคารอาคารสงเคราะห์',
      _ => code.trim(),
    };

/// Bank codes offered when the customer names their own payout account.
///
/// Deliberately the same set [bankDisplayName] can render, so a picked code
/// never falls through to its raw form. An Extra never sees this list — its
/// account comes off the contract.
const List<String> kPayoutBankCodes = [
  'KBANK', 'SCB', 'BBL', 'KTB', 'BAY', 'TTB', 'GSB', 'BAAC', 'LHB', 'CIMB',
  'UOB', 'GHB',
];

/// Full-width bottom sheet listing [options]; pops the chosen one.
///
/// The flow's screens are otherwise read-only, so this is the one input idiom
/// they need — used for the collateral type and the payout bank.
Future<T?> pickPLoanOption<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required String Function(T) labelOf,
  T? selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: LoanRegisterStyles.appBarTitleStyle()
                          .copyWith(fontSize: 17)),
                ),
                IconButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  icon: Icon(Icons.close, color: LoanRegisterStyles.label),
                ),
              ],
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final option in options)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        labelOf(option),
                        style: GoogleFonts.notoSansThai(
                          fontSize: 15,
                          color: LoanRegisterStyles.value,
                        ),
                      ),
                      trailing: option == selected
                          ? Icon(Icons.check_circle,
                              color: LoanRegisterStyles.primary, size: 22)
                          : null,
                      onTap: () => Navigator.of(sheetContext).pop(option),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// SVG for a loan-type code, matching the source's per-code mapping.
String loanTypeIconAsset(String loanTypeCode) =>
    switch (loanTypeCode.trim().toUpperCase()) {
      'C' => 'assets/p_loan/car-loan.svg',
      'M' => 'assets/p_loan/MotorLoanIcon.svg',
      'H' || 'L' => 'assets/p_loan/HouseLoanIcon.svg',
      'T' => 'assets/p_loan/LOANT.svg',
      'V' => 'assets/p_loan/LOANV.svg',
      'I' => 'assets/p_loan/CarInsuranceLoanIcon.svg',
      _ => 'assets/p_loan/LOANL.svg',
    };

/// Decodes a base64 image (raw or `data:` URL) or returns null when absent or
/// malformed — the bank logo arrives inline in the loan-list payload.
Uint8List? decodeBase64Image(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;
  final payload =
      text.startsWith('data:') ? text.substring(text.indexOf(',') + 1) : text;
  try {
    return base64Decode(payload);
  } catch (_) {
    return null;
  }
}

// ── widgets ───────────────────────────────────────────────────────────

/// Section heading: a thick orange rule then the label. The recurring header
/// idiom across the flow's screens.
class PLoanSectionHeader extends StatelessWidget {
  const PLoanSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Container(width: 3, height: 18, color: LoanRegisterStyles.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.notoSansThai(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: LoanRegisterStyles.value,
            ),
          ),
        ],
      ),
    );
  }
}

/// A label/value row. [emphasis] renders both sides in red, which the source
/// uses for the payout and any extra-limit line.
class PLoanAmountRow extends StatelessWidget {
  const PLoanAmountRow({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.emphasis = false,
    this.large = false,
    this.showDivider = true,
  });

  final String label;
  final String value;

  /// Small grey line under the label (e.g. `เลขที่สัญญา …`).
  final String? caption;
  final bool emphasis;
  final bool large;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final color = emphasis ? LoanRegisterStyles.required : LoanRegisterStyles.value;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.notoSansThai(
                        fontSize: 14,
                        color: emphasis
                            ? LoanRegisterStyles.required
                            : LoanRegisterStyles.label,
                      ),
                    ),
                    if (caption != null && caption!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        caption!,
                        style: GoogleFonts.notoSansThai(
                          fontSize: 12,
                          color: LoanRegisterStyles.label,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                value,
                textAlign: TextAlign.right,
                style: GoogleFonts.notoSansThai(
                  fontSize: large ? 21 : 15,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: LoanRegisterStyles.divider),
      ],
    );
  }
}

/// Header card identifying the contract the request is raised against —
/// the flow's equivalent of the source's `LoanDetailCardTopupComponent`.
class ContractSummaryCard extends StatelessWidget {
  const ContractSummaryCard({
    super.key,
    required this.loanTypeCode,
    required this.loanTypeName,
    required this.contractNo,
    required this.collateralInformation,
  });

  final String loanTypeCode;
  final String loanTypeName;
  final String contractNo;
  final String collateralInformation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LoanRegisterStyles.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SvgPicture.asset(loanTypeIconAsset(loanTypeCode),
              width: 44, height: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loanTypeName.isEmpty ? 'สินเชื่อ' : loanTypeName,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: LoanRegisterStyles.value,
                  ),
                ),
                const SizedBox(height: 4),
                _line('เลขที่สัญญา', contractNo),
                _line('ข้อมูลหลักประกัน', collateralInformation),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '$label $value',
        style: GoogleFonts.notoSansThai(
          fontSize: 12,
          color: LoanRegisterStyles.label,
        ),
      ),
    );
  }
}

/// Bank account card (logo + bank name + account number), shown on steps 5
/// and 6 and in the confirm sheet.
class BankAccountCard extends StatelessWidget {
  const BankAccountCard({
    super.key,
    required this.bankCode,
    required this.accountNo,
    this.logoBytes,
  });

  final String bankCode;
  final String accountNo;
  final Uint8List? logoBytes;

  @override
  Widget build(BuildContext context) {
    final logo = logoBytes;
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LoanRegisterStyles.cardBorder),
      ),
      child: Row(
        children: [
          if (logo != null && logo.isNotEmpty) ...[
            ClipOval(
                child: Image.memory(logo,
                    width: 50, height: 50, fit: BoxFit.cover)),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bankDisplayName(bankCode),
                  style: GoogleFonts.notoSansThai(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: LoanRegisterStyles.value,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  accountNo,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: LoanRegisterStyles.value,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen error state with a retry action. The source showed a modal
/// dialog and then popped the screen, which left the user with nothing to act
/// on; this keeps them on the screen and lets them retry.
class PLoanErrorView extends StatelessWidget {
  const PLoanErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 56, color: LoanRegisterStyles.required),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansThai(
                fontSize: 15,
                color: LoanRegisterStyles.value,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: LoanRegisterStyles.primary),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 12),
                ),
                child: Text(
                  'ลองใหม่',
                  style: GoogleFonts.notoSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: LoanRegisterStyles.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Centred spinner with an optional Thai caption.
class PLoanLoadingView extends StatelessWidget {
  const PLoanLoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: LoanRegisterStyles.primary),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: GoogleFonts.notoSansThai(
                fontSize: 14,
                color: LoanRegisterStyles.label,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Strip shown on every screen of the flow while [PLoanApi.isMocked] is on.
///
/// Deliberately loud and always visible: without it, a screen full of
/// plausible-looking contract numbers and payout figures is indistinguishable
/// from live data, and the final screen would claim a request had been filed.
class PLoanMockBanner extends StatelessWidget {
  const PLoanMockBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!PLoanApi.isMocked) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF4CE),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.science_outlined, size: 16, color: Color(0xFF8A6100)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'โหมดทดสอบ — ข้อมูลจำลอง ยังไม่ได้เชื่อมต่อระบบจริง',
              style: GoogleFonts.notoSansThai(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF8A6100),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// White app bar with an orange title, matching the rest of the app.
/// Thin strip naming the product, shown on every screen of a **new** P-Loan.
///
/// Only for [PLoanKind.newLoan]: the two kinds share all six screens, and the
/// Extra is the long-standing default, so marking only the new one keeps that
/// flow visually unchanged while making it impossible to be in the new one
/// without knowing it.
class PLoanKindBanner extends StatelessWidget {
  const PLoanKindBanner({super.key, required this.kind});

  final PLoanKind kind;

  @override
  Widget build(BuildContext context) {
    if (kind != PLoanKind.newLoan) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: LoanRegisterStyles.primarySoft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.request_quote_outlined,
              size: 15, color: LoanRegisterStyles.primary),
          const SizedBox(width: 6),
          Text(
            kind.label,
            style: GoogleFonts.notoSansThai(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: LoanRegisterStyles.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Carries [EnvVersionTag] like every wizard page does, so a tester can read
/// the env + build off any screen of the flow. Set here rather than per page
/// because all six share this helper.
///
/// [onBack] replaces the default pop. Needed by whichever screen is the flow's
/// **entry point**: a deep-linked step 3 has nothing beneath it on the stack,
/// so back must close the WebView instead of popping to a blank route.
AppBar pLoanAppBar(BuildContext context, String title, {VoidCallback? onBack}) =>
    AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: BackButton(color: LoanRegisterStyles.primary, onPressed: onBack),
      centerTitle: true,
      title: Text(
        title,
        style: LoanRegisterStyles.appBarTitleStyle()
            .copyWith(color: LoanRegisterStyles.primary),
      ),
      actions: const [EnvVersionTag()],
    );

/// Single sticky primary button, the flow's standard bottom bar. [onPressed]
/// null renders it disabled.
class PLoanBottomButton extends StatelessWidget {
  const PLoanBottomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: LoanRegisterStyles.divider)),
      ),
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: LoanRegisterStyles.primary,
            disabledBackgroundColor: LoanRegisterStyles.primary.withValues(
              alpha: 0.5,
            ),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  label,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}
