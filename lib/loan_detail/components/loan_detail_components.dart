/// Building blocks for the **รายละเอียดสินเชื่อ** screen.
///
/// ⚠ **This screen family carries its own palette** ([LoanDetailPalette]),
/// like the top-up QR screen and for the same reason: it is a screen the
/// customer already knows from the srisawad mobile app, and two
/// different-looking versions of *their own contract* invites doubt about
/// which one is telling the truth. So the navy, the label grey and the red are
/// quoted from that app rather than taken from [LoanRegisterStyles], and the
/// difference is visible — its navy is `#003063` where this repo's value blue
/// is `#1B3A6B`. **That trade does not generalise**; don't copy the pattern
/// onto a screen this build owns outright.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hexcolor/hexcolor.dart';

import '../../loan_register/components/env_version_tag.dart';
import '../../loan_register/components/loan_register_styles.dart';

/// The srisawad mobile app's own colours for this screen. See the library note.
class LoanDetailPalette {
  LoanDetailPalette._();

  /// Headings, figures and the selected tab chip.
  static Color get navy => HexColor('#003063');

  /// Row labels and read-only text.
  static Color get label => const Color.fromRGBO(64, 64, 64, 1);

  /// The `ข้อมูลวันที่ …` footer.
  static Color get muted => const Color.fromRGBO(138, 152, 167, 1);

  /// Warnings, overdue figures and the "not yet issued" notice. Pure red, as
  /// the source has it — not [LoanRegisterStyles.required].
  static Color get alert => HexColor('#FF0000');

  static Color get divider => HexColor('#E5E5E5');

  /// Strip behind the tab chips.
  static Color get tabBar => HexColor('#FAFAFA');

  /// The คู่สัญญา / คำขอออกตั๋ว button — a soft peach fill with orange text,
  /// not the flow's solid orange primary.
  static Color get contractButtonFill => const Color(0xFFFCEFE4);
  static Color get contractButtonText => const Color(0xFFDB771A);
}

/// AppBar for this screen and its sub-pages.
///
/// Carries [EnvVersionTag] like every other screen here, so a tester can read
/// the env and build number off it. Hidden on prod.
AppBar loanDetailAppBar(
  BuildContext context,
  String title, {
  VoidCallback? onBack,
}) =>
    AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: BackButton(color: LoanDetailPalette.navy, onPressed: onBack),
      centerTitle: true,
      title: Text(
        title,
        style: GoogleFonts.notoSansThai(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: LoanDetailPalette.label,
        ),
      ),
      actions: const [EnvVersionTag()],
    );

// ── formatting ────────────────────────────────────────────────────────

const List<String> _kThaiMonthAbbreviations = [
  'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
];

/// `2026-07-14T13:30:00` → `'13.30'`. The source's `formateTime`: a dot
/// separator, not a colon, and `''` for anything unparseable.
String formatLoanDetailTime(String? raw) {
  final parsed = DateTime.tryParse((raw ?? '').trim());
  if (parsed == null) return '';
  return '${parsed.hour.toString().padLeft(2, '0')}.'
      '${parsed.minute.toString().padLeft(2, '0')}';
}

/// `14 ก.ค. 68` — the source's `returnThaiDateFormat`, including its
/// **two-digit** Buddhist year (it slices characters 2-3 out of `'2568'`).
String formatThaiShortDate(DateTime? date) {
  if (date == null) return '';
  final year = (date.year > 2200 ? date.year : date.year + 543).toString();
  final shortYear = year.length >= 4 ? year.substring(2, 4) : year;
  final month = _kThaiMonthAbbreviations[date.month - 1];
  return '${date.day.toString().padLeft(2, '0')} $month $shortYear';
}

/// The inline SVG the API sends as `contract_details.loan_type_icon`.
///
/// It arrives as a `data:image/svg+xml;charset=utf-8,<svg …>` URL, which the
/// source renders by stripping the prefix and handing the rest to
/// `SvgPicture.string`. Anything empty or unrecognisable renders as blank
/// space of the same size rather than an error glyph — a missing icon must not
/// be louder than the contract name beside it.
class LoanTypeIcon extends StatelessWidget {
  const LoanTypeIcon({super.key, required this.dataUrl, this.size = 52});

  final String dataUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final markup = _svgMarkup(dataUrl);
    if (markup == null) return SizedBox(width: size, height: size);
    return SvgPicture.string(
      markup,
      width: size,
      height: size,
      placeholderBuilder: (_) => SizedBox(width: size, height: size),
    );
  }

  static String? _svgMarkup(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    const prefix = 'data:image/svg+xml;charset=utf-8,';
    if (text.startsWith(prefix)) text = text.substring(prefix.length);
    // The `charset=utf-8` in that prefix means the payload *may* be
    // percent-encoded. The live one is not — the source strips and renders it
    // straight — so decode only when the markup plainly is, rather than
    // running every payload through a decoder that would mangle a legitimate
    // `%` inside an SVG attribute.
    if (!text.contains('<') && (text.contains('%3C') || text.contains('%3c'))) {
      try {
        text = Uri.decodeFull(text);
      } catch (_) {
        return null;
      }
    }
    return text.contains('<svg') ? text : null;
  }
}

// ── rows ──────────────────────────────────────────────────────────────

/// A label/value pair inside the header card: small grey label on the left,
/// the value on the right.
class LoanDetailSummaryRow extends StatelessWidget {
  const LoanDetailSummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasised = false,
    this.trailing,
  });

  final String label;
  final String value;
  final Color? valueColor;

  /// Figures are semibold navy; plain facts (the contract number, the due
  /// date) are regular grey.
  final bool emphasised;

  /// Replaces [value] — used by the กรมธรรม์ row, whose right-hand side is a
  /// link rather than a value.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            label,
            style: GoogleFonts.notoSansThai(
              fontSize: 14,
              height: 1.5,
              color: LoanDetailPalette.label,
            ),
          ),
        ),
        const SizedBox(width: 8),
        trailing ??
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: GoogleFonts.notoSansThai(
                  fontSize: 14,
                  height: 1.5,
                  fontWeight:
                      emphasised ? FontWeight.w600 : FontWeight.w400,
                  color: valueColor ??
                      (emphasised
                          ? LoanDetailPalette.navy
                          : LoanDetailPalette.label),
                ),
              ),
            ),
      ],
    );
  }
}

/// A full-width row in the tab body: label left, value + unit right, on white,
/// with a hairline rule under it.
class LoanDetailFieldRow extends StatelessWidget {
  const LoanDetailFieldRow({
    super.key,
    required this.label,
    required this.value,
    this.suffix = '',
  });

  final String label;
  final String value;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final valueStyle = GoogleFonts.notoSansThai(
      fontSize: 16,
      height: 1,
      fontWeight: FontWeight.w600,
      color: LoanDetailPalette.label,
    );
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(24, 21, 27, 15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  label,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 14,
                    height: 1,
                    color: LoanDetailPalette.label,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: Text(
                  suffix.isEmpty ? value : '$value $suffix',
                  textAlign: TextAlign.end,
                  style: valueStyle,
                ),
              ),
            ],
          ),
        ),
        Container(height: 1, color: LoanDetailPalette.divider),
      ],
    );
  }
}

/// `ข้อมูลวันที่ dd/MM/yyyy เวลา HH.mm น.` — closes every tab body.
class LoanDetailDataDateFooter extends StatelessWidget {
  const LoanDetailDataDateFooter({
    super.key,
    required this.date,
    required this.time,
  });

  final String date;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(22),
      child: Center(
        child: Text(
          'ข้อมูลวันที่ $date เวลา $time น.',
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSansThai(
            fontSize: 12,
            height: 1,
            color: LoanDetailPalette.muted,
          ),
        ),
      ),
    );
  }
}

/// One pill in the horizontal tab strip (the source's `SlidingLoanOptions`).
class LoanDetailTabChip extends StatelessWidget {
  const LoanDetailTabChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 5, right: 5, bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.16),
                spreadRadius: 2,
                blurRadius: 7,
                offset: const Offset(0, 3),
              ),
            ],
            color: selected ? LoanDetailPalette.navy : Colors.white,
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansThai(
                fontSize: 16,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : LoanDetailPalette.navy,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The เวลา/จำนวนเงิน/ช่องทาง card in the ประวัติการชำระ tab.
class PaymentHistoryCard extends StatelessWidget {
  const PaymentHistoryCard({
    super.key,
    required this.headingDate,
    required this.paidAtLabel,
    required this.amount,
    required this.channel,
  });

  final String headingDate;
  final String paidAtLabel;
  final String amount;
  final String channel;

  @override
  Widget build(BuildContext context) {
    final rowStyle = GoogleFonts.notoSansThai(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF646464),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headingDate,
            style: GoogleFonts.notoSansThai(
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 4,
                  color: Color(0x33000000),
                  offset: Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paidAtLabel,
                  style: GoogleFonts.notoSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: LoanDetailPalette.navy,
                  ),
                ),
                const SizedBox(height: 12),
                _row('จำนวนเงิน', amount, rowStyle),
                const SizedBox(height: 12),
                _row('ช่องทางการชำระ', channel, rowStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _row(String label, String value, TextStyle style) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: style),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value, textAlign: TextAlign.end, style: style),
          ),
        ],
      );
}
