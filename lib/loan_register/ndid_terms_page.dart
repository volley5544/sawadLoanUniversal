import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/ndid_subject.dart';
import '../router/app_router.dart';
import '../services/diagnostics.dart';
import 'components/env_version_tag.dart';
import 'components/loan_register_styles.dart';
import 'ndid_terms_content.dart';

/// เงื่อนไขและข้อตกลงที่เกี่ยวข้อง NDID — the service agreement the customer
/// accepts before any NDID identity verification runs.
///
/// **This is the entry point of the NDID sub-flow.** Both flows that verify an
/// identity now push here rather than straight at the IdP picker:
///
/// ```
/// wizard step 4   → document_review_page ┐
/// P-Loan step 6   → p_loan_conclusion    ┘→ ndid_terms → ndid_bank_select → ndid_verify
/// ```
///
/// It takes an [NdidSubject] purely to hand onward — like the two screens after
/// it, it needs nothing from the flow itself, which is why one page serves both.
/// Accepting pushes the IdP picker and propagates its `true` back up the chain
/// unchanged, so a caller still just awaits one bool and cannot tell the extra
/// screen was inserted.
///
/// The agreement is **one continuous scroll**, not a pager: the clauses are read
/// top to bottom in the order the document has them.
///
/// Acceptance is **not** remembered on the flow: every run of the NDID hop
/// shows the agreement again. That is deliberate for a consent — the customer
/// agrees to this verification, not to verification in general.
class NdidTermsPage extends StatelessWidget {
  const NdidTermsPage({super.key, this.form});

  /// The flow that launched the NDID hop — the wizard's form or the P-Loan
  /// flow. Passed straight through to the IdP picker.
  final NdidSubject? form;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        actions: const [EnvVersionTag()],
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: LoanRegisterStyles.primary),
        centerTitle: true,
        title: Text('เงื่อนไขและข้อตกลงที่เกี่ยวข้อง NDID',
            style: LoanRegisterStyles.appBarTitleStyle().copyWith(fontSize: 15)),
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Expanded(child: _card()),
          _bottomBar(context),
        ],
      ),
    );
  }

  Widget _card() {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: LoanRegisterStyles.padding),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: LoanRegisterStyles.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading(),
                const SizedBox(height: 18),
                for (final clause in kNdidTermsClauses) _clause(clause),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The document's own heading, centred as the source has it.
  Widget _heading() {
    return Center(
      child: Column(
        children: [
          Text(
            kNdidTermsTitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansThai(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: LoanRegisterStyles.value,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            kNdidTermsIssuer,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansThai(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: LoanRegisterStyles.value,
            ),
          ),
        ],
      ),
    );
  }

  Widget _clause(NdidTermsClause clause) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < clause.paragraphs.length; i++)
            _hangingRow(
              // Only the first paragraph carries the number; the rest of the
              // clause lines up under it, as the source document has them.
              marker: i == 0 ? '${clause.number}.' : '',
              text: clause.paragraphs[i],
              markerWidth: 22,
              bottom: i == clause.paragraphs.length - 1 ? 0 : 8,
            ),
          for (final item in clause.items)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 8),
              child: _hangingRow(
                marker: item.marker,
                text: item.text,
                markerWidth: 30,
                bottom: 0,
              ),
            ),
        ],
      ),
    );
  }

  /// A numbered paragraph: the marker in a fixed-width gutter, the body
  /// wrapping beside it rather than under it.
  Widget _hangingRow({
    required String marker,
    required String text,
    required double markerWidth,
    required double bottom,
  }) {
    final style = GoogleFonts.notoSansThai(
      fontSize: 13,
      height: 1.6,
      color: LoanRegisterStyles.value,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: markerWidth,
            child: Text(marker,
                style: style.copyWith(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text(text, style: style, textAlign: TextAlign.start),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            LoanRegisterStyles.padding, 12, LoanRegisterStyles.padding, 12),
        child: Row(
          children: [
            Expanded(
              child: _TermsButton(
                label: 'ปฏิเสธ',
                filled: false,
                onTap: () => _decline(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TermsButton(
                label: 'ยอมรับ',
                filled: true,
                onTap: () => _accept(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Declining ends the NDID hop. Recorded in the diagnostics trail per the
  /// design's "กรณีปฏิเสธมีเก็บ log" note — that trail is local to the session
  /// and readable from the `(UAT ver…)` tag; there is no consent-log endpoint
  /// to post it to yet.
  void _decline(BuildContext context) {
    Diagnostics.log('ndid terms declined');
    context.pop(false);
  }

  Future<void> _accept(BuildContext context) async {
    Diagnostics.log('ndid terms accepted');
    final ok = await context.push<bool>(
      AppRoutes.ndidBankSelect,
      extra: form,
    );
    // Pass the verification result straight through, so the caller sees the
    // same bool it saw before this screen existed.
    if (ok == true && context.mounted) context.pop(true);
  }
}

class _TermsButton extends StatelessWidget {
  const _TermsButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color primary = LoanRegisterStyles.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? primary : LoanRegisterStyles.primarySoft,
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
