/// **กรมธรรม์** — the insurance policies attached to a contract.
///
/// Reached from the loan detail header's ดูรายละเอียด link, and only shown
/// when `insurances` is non-empty. Ported from the srisawad app's
/// `vmi_list_page.dart`, which renders one card per policy carrying the
/// insurer's name and a ดาวน์โหลด button.
///
/// ⚠ **That page's other rows are `Visibility(visible: false)`** — customer
/// name, sum insured, cover dates. They are hidden in the shipped app, so they
/// are not reproduced here; reinstating them is a design decision, not a port
/// omission.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../p_loan/application/models/loan_contract.dart';
import '../router/app_router.dart';
import 'components/loan_detail_components.dart';
import 'loan_detail_page.dart' show openExternalDocument;

class InsuranceListPage extends StatelessWidget {
  const InsuranceListPage({super.key, required this.insurances});

  final List<Insurance> insurances;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: loanDetailAppBar(
        context,
        'กรมธรรม์',
        onBack: () =>
            context.canPop() ? context.pop() : context.go(AppRoutes.home),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 15, 20, 24),
          children: [
            for (final insurance in insurances)
              _InsuranceCard(insurance: insurance),
          ],
        ),
      ),
    );
  }
}

class _InsuranceCard extends StatelessWidget {
  const _InsuranceCard({required this.insurance});

  final Insurance insurance;

  @override
  Widget build(BuildContext context) {
    final url = insurance.insUrl.trim();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 4,
            color: Color(0x33000000),
            offset: Offset(2, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 35,
                height: 35,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE1BD8A)),
                ),
                child: const Icon(
                  Icons.health_and_safety_outlined,
                  color: Color(0xFFE1BD8A),
                  size: 20,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  insurance.insName.trim(),
                  style: GoogleFonts.notoSansThai(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: LoanDetailPalette.navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Center(
            child: GestureDetector(
              // A policy with no URL gets no button — the source would call
              // `launchURL('')`, which does nothing and looks like a broken tap.
              onTap: url.isEmpty
                  ? null
                  : () => openExternalDocument(context, url),
              child: Opacity(
                opacity: url.isEmpty ? 0.4 : 1,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.circular(24)),
                    color: LoanDetailPalette.navy,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withValues(alpha: 0.16),
                        spreadRadius: 2,
                        blurRadius: 7,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    'ดาวน์โหลด',
                    style: GoogleFonts.notoSansThai(
                      fontSize: 16,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
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
