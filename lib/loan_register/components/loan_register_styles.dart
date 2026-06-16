import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hexcolor/hexcolor.dart';

/// Shared colors / text styles for the loan-register (สมัครสินเชื่อ) flow.
///
/// Kept in one place so all step pages and selector screens stay visually
/// consistent. Colors are eyeballed from the design (slide 7) and reuse the
/// app's existing NotoSansThai font + HexColor convention.
class LoanRegisterStyles {
  LoanRegisterStyles._();

  static const double padding = 22;

  static Color get primary => HexColor('#E8842A'); // orange action color
  static Color get primarySoft => HexColor('#FDEEDD'); // light orange fill
  static Color get value => HexColor('#1B3A6B'); // dark-blue field value
  static Color get label => HexColor('#9AA0A6'); // grey field label
  static Color get divider => HexColor('#ECECEC');
  static Color get cardBorder => HexColor('#E3E6EA');
  static Color get required => HexColor('#E53935'); // red required hint
  static Color get background => Colors.white;

  static TextStyle labelStyle() => GoogleFonts.notoSansThai(
        fontSize: 13,
        color: label,
        fontWeight: FontWeight.w400,
      );

  static TextStyle valueStyle() => GoogleFonts.notoSansThai(
        fontSize: 16,
        color: value,
        fontWeight: FontWeight.w600,
      );

  static TextStyle sectionTitleStyle() => GoogleFonts.notoSansThai(
        fontSize: 16,
        color: value,
        fontWeight: FontWeight.w700,
      );

  static TextStyle appBarTitleStyle() => GoogleFonts.notoSansThai(
        fontSize: 17,
        color: value,
        fontWeight: FontWeight.w600,
      );

  static TextStyle requiredStyle() => GoogleFonts.notoSansThai(
        fontSize: 12,
        color: required,
        fontWeight: FontWeight.w400,
      );
}
