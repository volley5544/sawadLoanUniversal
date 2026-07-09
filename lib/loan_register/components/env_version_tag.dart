import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_environment.dart';
import 'loan_register_styles.dart';

/// Small "(UAT ver12)" tag placed in every page's AppBar `actions`, so testers
/// can see at a glance which environment + build (`WEB_VERSION`, the CI run
/// number) the WebView is actually running. Hidden on prod builds; local dev
/// builds show "(UAT ver0)" (the defines' defaults).
class EnvVersionTag extends StatelessWidget {
  const EnvVersionTag({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (AppEnvironment.current.isProd) return const SizedBox.shrink();
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Text(
          '(UAT ver$kWebVersion)',
          style: GoogleFonts.notoSansThai(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: LoanRegisterStyles.label,
          ),
        ),
      ),
    );
  }
}
