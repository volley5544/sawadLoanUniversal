/// Shared pieces of the **2026-09 top-up redesign** — the card screen and the
/// amount screen, rebuilt from
/// `etc/M35 + หน้าจอเติมเงิน_ปิดปรับผ่านแอพมือถือ_หลั.pdf`.
///
/// Both screens are one design, so their palette, their money row and their
/// deduction rows live here rather than being written twice and drifting. The
/// pre-redesign screens are preserved at `/topup/old` and `/topup/amount-old`
/// and deliberately share **nothing** with this file, so editing the redesign
/// cannot change what those two render.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../loan_register/components/loan_register_styles.dart';

/// The redesign's own colours.
///
/// ⚠ **This page family carries its own palette**, like the QR screen does and
/// for a related reason: the design is the BA's, handed over as renders, and
/// its blues are not [LoanRegisterStyles]' blues — the band is a saturated
/// mid-blue where `LoanRegisterStyles.value` is a muted navy, and the strip
/// under it is a tint of the band rather than the app's grey-blue card fill.
/// Matching the approved renders beat matching the rest of the app here; that
/// trade does **not** generalise, so don't copy this pattern onto another
/// screen. Text keeps [LoanRegisterStyles] wherever the design agrees with it.
class TopupTheme {
  TopupTheme._();

  /// The ข้อเสนอพิเศษสำหรับคุณ band, and the วงเงินสินเชื่อใหม่สูงสุด bar on
  /// the amount screen — the same blue in both places by design.
  static const Color band = Color(0xFF1668B8);

  /// The เงินคงเหลือโอนเข้าบัญชีสูงสุด strip: a tint of [band].
  static const Color strip = Color(0xFFE7F1FA);

  /// The `can_topup = N` header, and the ข้อมูลสถานะ pill.
  static const Color warnBand = Color(0xFFFDEEE2);
  static const Color warnPillText = Color(0xFFD2691E);

  /// The red used for the two footnotes and the warning glyph. Pure red, as
  /// drawn — not [LoanRegisterStyles.required], which is a softer material red.
  static const Color alert = Color(0xFFE02020);

  static const Color hairline = Color(0xFFDFE4EA);

  static TextStyle label({double size = 13.5, Color? color}) =>
      GoogleFonts.notoSansThai(
        fontSize: size,
        color: color ?? LoanRegisterStyles.label,
        height: 1.45,
      );

  /// A section heading — the orange labels the design leads its blocks with,
  /// and the navy ones inside a card.
  static TextStyle heading({double size = 15, Color? color}) =>
      GoogleFonts.notoSansThai(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? LoanRegisterStyles.value,
      );

  /// Running text — bullets, notes, anything that wraps.
  static TextStyle body({double size = 13, Color? color}) =>
      GoogleFonts.notoSansThai(
        fontSize: size,
        height: 1.5,
        color: color ?? LoanRegisterStyles.value,
      );

  static TextStyle value({
    double size = 15,
    FontWeight weight = FontWeight.w600,
    Color? color,
  }) =>
      GoogleFonts.notoSansThai(
        fontSize: size,
        fontWeight: weight,
        color: color ?? LoanRegisterStyles.value,
      );
}

/// Money as `#,##0.00` — **always two decimals**, which is the redesign's
/// whole numeric style.
///
/// The old screens round to whole baht in places. Here they cannot: the card
/// and the amount screen both show a subtotal, two deductions and a result,
/// and a reader who adds up three rounded rows and gets a different total has
/// found a bug in the app rather than in their arithmetic. `86,217.08` is also
/// what the wire sends.
String formatTopupMoney(num value) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final whole = fixed.substring(0, dot);
  final fraction = fixed.substring(dot);
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
    grouped.write(whole[i]);
  }
  return '${negative ? '-' : ''}$grouped$fraction';
}

/// A dotted rule, drawn rather than imported — the design separates the
/// contract block from the figures with one, and a solid divider reads as a
/// harder break than intended.
class TopupDottedDivider extends StatelessWidget {
  const TopupDottedDivider({super.key, this.color = TopupTheme.hairline});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dash = 3.0;
        const gap = 4.0;
        final count = (constraints.maxWidth / (dash + gap)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => SizedBox(
              width: dash,
              height: 1,
              child: DecoratedBox(decoration: BoxDecoration(color: color)),
            ),
          ),
        );
      },
    );
  }
}

/// One `label … value` line. [emphasis] is the บาท-suffixed headline row
/// (วงเงินสินเชื่อใหม่สูงสุด), [deduction] the smaller signed rows under it.
class TopupFigureRow extends StatelessWidget {
  const TopupFigureRow({
    super.key,
    required this.label,
    required this.amount,
    this.caption = '',
    this.emphasis = false,
    this.deduction = false,
    this.suffix = '',
    this.valueColor,
  });

  final String label;
  final num amount;

  /// A second, smaller line under [label] — the design puts the contract
  /// number there on the principal row.
  final String caption;

  final bool emphasis;

  /// Renders the amount negative **and greys the whole row**, which is how the
  /// design shows the two lines that come off the new limit.
  ///
  /// The value is muted along with its label on purpose (set 2026-09-12 from a
  /// device check): these rows are working, not conclusions. Leaving the
  /// figures in the value navy gave a deduction the same weight as the payout
  /// under it, so the eye found three equal numbers instead of two small ones
  /// explaining a large one. [valueColor] still overrides.
  final bool deduction;

  final String suffix;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final text = formatTopupMoney(deduction ? -amount.abs() : amount);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: emphasis
                      ? TopupTheme.value(size: 15, weight: FontWeight.w700)
                      : TopupTheme.label(),
                ),
                if (caption.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(caption,
                        style: TopupTheme.label(size: 11.5)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: emphasis
                ? TopupTheme.value(
                    size: 22, weight: FontWeight.w800, color: valueColor)
                : TopupTheme.value(
                    size: 13.5,
                    weight: FontWeight.w600,
                    color: valueColor ??
                        (deduction ? LoanRegisterStyles.label : null),
                  ),
          ),
          if (suffix.isNotEmpty) ...[
            const SizedBox(width: 6),
            Padding(
              padding: EdgeInsets.only(top: emphasis ? 8 : 0),
              child: Text(suffix, style: TopupTheme.label(size: 13)),
            ),
          ],
        ],
      ),
    );
  }
}

/// The peach `ข้อมูลสถานะ` pill — `⏱ ไม่เข้าเงื่อนไข`, or the
/// not-yet-requested line.
class TopupStatusPill extends StatelessWidget {
  const TopupStatusPill({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: TopupTheme.warnBand,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: TopupTheme.warnPillText),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              style: GoogleFonts.notoSansThai(
                fontSize: 11.5,
                color: TopupTheme.warnPillText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The contract block both screens lead with: a round type glyph, the product
/// name, and the three identifying rows.
class TopupContractHeader extends StatelessWidget {
  const TopupContractHeader({
    super.key,
    required this.loanTypeCode,
    required this.loanTypeName,
    required this.contractNo,
    required this.collateralInformation,
    this.status,
  });

  final String loanTypeCode;
  final String loanTypeName;
  final String contractNo;
  final String collateralInformation;

  /// The ข้อมูลสถานะ pill. Omitted entirely when null — the amount screen
  /// shows no status, having already acted on it.
  final Widget? status;

  /// Material glyph for a loan type. `M` motorcycle, `C` car, `L`/`H` land or
  /// house; anything else gets the neutral document mark rather than a guess.
  static IconData iconFor(String code) {
    switch (code.toUpperCase()) {
      case 'M':
        return Icons.two_wheeler_outlined;
      case 'C':
        return Icons.directions_car_outlined;
      case 'L':
      case 'H':
        return Icons.home_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: LoanRegisterStyles.primarySoft, width: 2),
          ),
          child: Icon(iconFor(loanTypeCode),
              size: 24, color: LoanRegisterStyles.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loanTypeName.isEmpty ? 'สินเชื่อ' : loanTypeName,
                style: TopupTheme.value(size: 16, weight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              _row('เลขที่สัญญา', Text(contractNo,
                  style: TopupTheme.value(size: 12.5,
                      weight: FontWeight.w500))),
              _row('ข้อมูลหลักประกัน', Text(collateralInformation,
                  style: TopupTheme.value(size: 12.5,
                      weight: FontWeight.w500))),
              if (status != null) _row('ข้อมูลสถานะ:', status!),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: TopupTheme.label(size: 12.5)),
          ),
          Expanded(
            flex: 5,
            child: Align(alignment: Alignment.centerRight, child: value),
          ),
        ],
      ),
    );
  }
}

/// **วิธีขอปรับวงเงินเพิ่ม** — the conditions panel, in the redesign's text
/// treatment.
///
/// ⚠ **A near-copy of `TopupConditionsPanel`, deliberately.** That widget is
/// still rendered by `topup_card_page_old.dart`, and the whole point of the
/// `_old` pair is that editing the redesign cannot change what they show — so
/// this restyles rather than mutates, and the copy lives here until the `_old`
/// pages are deleted, at which point the original goes with them and this
/// becomes the only one. The **wording is identical**; only the type and the
/// red differ.
class TopupConditionsCard extends StatelessWidget {
  const TopupConditionsCard({super.key});

  static const List<String> bullets = [
    'จ่ายตรง -> เครดิตดี -> ได้วงเงินเพิ่ม',
    'จ่ายช้า -> ขอปรับสัญญาที่สาขา -> รักษาเครดิต -> ปรับวงเงินเพิ่ม',
  ];

  static const List<String> notes = [
    '* สามารถทำการขอเติมวงเงินได้เวลาทำการ 07.00 - 20.30 น.',
    '** เงื่อนไขอาจมีการเปลี่ยนแปลงได้ โดยไม่ต้องแจ้งให้ทราบล่วงหน้า',
    '*** บริษัทจะดำเนินการโอนเงินภายใน 30 นาที ในวันและเวลาทำการ '
        '07.00 - 20.30 น.',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          LoanRegisterStyles.padding, 10, LoanRegisterStyles.padding, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LoanRegisterStyles.primarySoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'วิธีขอปรับวงเงินเพิ่ม',
            style: TopupTheme.heading(color: LoanRegisterStyles.primary),
          ),
          const SizedBox(height: 8),
          for (final bullet in bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $bullet',
                  style: TopupTheme.body(color: LoanRegisterStyles.value)),
            ),
          const SizedBox(height: 4),
          // `TopupTheme.alert`, not `LoanRegisterStyles.required`: the design's
          // footnote red is pure, the app's is a softer material red, and these
          // notes sit beside the card's own red footnote.
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(note,
                  style: TopupTheme.body(size: 12.5, color: TopupTheme.alert)),
            ),
        ],
      ),
    );
  }
}
