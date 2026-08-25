import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_environment.dart';
import '../../services/diagnostics.dart';
import 'loan_register_styles.dart';

/// Small "(UAT ver12)" tag placed in every page's AppBar `actions`, so testers
/// can see at a glance which environment + build (`WEB_VERSION`, the CI run
/// number) the WebView is actually running. Hidden on prod builds; local dev
/// builds show "(UAT ver0)" (the defines' defaults).
///
/// **Tapping it opens the diagnostics sheet** ([showDiagnosticsSheet]): the
/// breadcrumb trail for this run and the one before it, copyable. That is the
/// only way a tester can hand us evidence — `isInspectable` is false on iOS so
/// Safari Web Inspector cannot attach, and the host's console output goes
/// somewhere they cannot see. It also reports a run that ended *without* an
/// error, which is what a killed WebView content process looks like.
///
/// Prod shows nothing at all, tag and sheet alike.
class EnvVersionTag extends StatelessWidget {
  const EnvVersionTag({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (AppEnvironment.current.isProd) return const SizedBox.shrink();
    return Center(
      child: GestureDetector(
        onTap: () => showDiagnosticsSheet(context),
        // The tag is 11pt text in an AppBar corner; without this only the glyphs
        // themselves would take the tap.
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(right: 12, left: 12, top: 8, bottom: 8),
          child: Text(
            '(UAT ver$kWebVersion)',
            style: GoogleFonts.notoSansThai(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: LoanRegisterStyles.label,
            ),
          ),
        ),
      ),
    );
  }
}
