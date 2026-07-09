import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'components/loan_register_styles.dart';

/// ค้นหาสาขา — web **fallback** branch picker (slide 9, search frame).
///
/// Inside the native host the branch is picked on the native map page
/// (`openBranchPicker` bridge handler — GPS + Google Maps live there). In a
/// plain browser there is no host, so this searchable list stands in. Pops the
/// chosen branch as a `Map<String, dynamic>` matching the bridge JSON
/// (`branchName`, `address`, `phone`, `lat`, `lng`), or nothing on back.
class BranchSelectPage extends StatefulWidget {
  const BranchSelectPage({Key? key}) : super(key: key);

  @override
  State<BranchSelectPage> createState() => _BranchSelectPageState();
}

class _BranchSelectPageState extends State<BranchSelectPage> {
  final TextEditingController _searchController = TextEditingController();
  int? _selectedIndex;

  /// Mock branches (slide 9 search frame). A real build would call the branch
  /// search API the native map uses.
  static const List<Map<String, String>> _branches = [
    {
      'branchName': 'สุขาภิบาล 1',
      'address': '604/14 ถ.นวมินทร์ แขวงคลองกุ่ม เขตบึงกุ่ม กรุงเทพมหานคร',
      'phone': '080-053-4281',
      'distance': '16.7 กม.',
      'lat': '13.7995',
      'lng': '100.6403',
    },
    {
      'branchName': 'สุขุมวิท 1',
      'address': '6 ซอย คลองตันเหนือ, เขตวัฒนา, กรุงเทพมหานคร',
      'phone': '080-053-4281',
      'distance': '1.3 กม.',
      'lat': '13.7431',
      'lng': '100.5490',
    },
    {
      'branchName': 'สุขุมวิท 101/1',
      'address':
          '6/14 ซอย สุขุมวิท101/1 ถนน สุขุมวิท แขวงบางจาก, เขตพระโขนง, กรุงเทพมหานคร 10260',
      'phone': '080-053-4281',
      'distance': '0.7 กม.',
      'lat': '13.6889',
      'lng': '100.6055',
    },
    {
      'branchName': 'สุขุมวิท 115',
      'address': '14 ถ.สุขุมวิท แขวงบางเมือง, อำเภอเมืองสมุทรปราการ',
      'phone': '080-053-4281',
      'distance': '10.4 กม.',
      'lat': '13.6288',
      'lng': '100.6093',
    },
    {
      'branchName': 'บางเมืองใหม่',
      'address': '56 ถ.สุขุมวิท 19 ต.บางเมืองใหม่, อำเภอเมืองสมุทรปราการ',
      'phone': '080-053-4281',
      'distance': '22.9 กม.',
      'lat': '13.5990',
      'lng': '100.6089',
    },
  ];

  List<int> get _matchIndexes {
    final query = _searchController.text.trim();
    return [
      for (var i = 0; i < _branches.length; i++)
        if (query.isEmpty ||
            _branches[i]['branchName']!.contains(query) ||
            _branches[i]['address']!.contains(query))
          i,
    ];
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _confirm() {
    final branch = _branches[_selectedIndex!];
    context.pop(<String, dynamic>{
      'branchName': branch['branchName'],
      'address': branch['address'],
      'phone': branch['phone'],
      'lat': branch['lat'],
      'lng': branch['lng'],
    });
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matchIndexes;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: LoanRegisterStyles.primary),
        centerTitle: true,
        title: Text('ค้นหาสาขา', style: LoanRegisterStyles.appBarTitleStyle()),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                LoanRegisterStyles.padding, 4, LoanRegisterStyles.padding, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() => _selectedIndex = null),
              style: GoogleFonts.notoSansThai(
                  fontSize: 15, color: LoanRegisterStyles.value),
              decoration: InputDecoration(
                hintText: 'ค้นหาสาขา',
                hintStyle: LoanRegisterStyles.labelStyle(),
                prefixIcon:
                    Icon(Icons.search, color: LoanRegisterStyles.label),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close,
                            size: 18, color: LoanRegisterStyles.label),
                        onPressed: () => setState(() {
                          _searchController.clear();
                          _selectedIndex = null;
                        }),
                      ),
                filled: true,
                fillColor: HexFill.searchFill,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                  horizontal: LoanRegisterStyles.padding),
              itemCount: matches.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: LoanRegisterStyles.divider),
              itemBuilder: (context, i) {
                final index = matches[i];
                final branch = _branches[index];
                final selected = index == _selectedIndex;
                return InkWell(
                  onTap: () => setState(() => _selectedIndex = index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          selected
                              ? Icons.location_on
                              : Icons.location_on_outlined,
                          size: 22,
                          color: selected
                              ? LoanRegisterStyles.primary
                              : LoanRegisterStyles.label,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                branch['branchName']!,
                                style: GoogleFonts.notoSansThai(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: LoanRegisterStyles.value,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(branch['address']!,
                                  style: LoanRegisterStyles.labelStyle()),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(branch['distance']!,
                            style: LoanRegisterStyles.labelStyle()),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(LoanRegisterStyles.padding, 4,
                  LoanRegisterStyles.padding, 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _selectedIndex == null ? null : _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: LoanRegisterStyles.primary,
                    disabledBackgroundColor: LoanRegisterStyles.cardBorder,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    'นัดหมาย',
                    style: GoogleFonts.notoSansThai(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
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

/// Light grey search-field fill (design's search frame).
class HexFill {
  HexFill._();
  static const Color searchFill = Color(0xFFF2F3F5);
}
