import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdc_admin_app/widgets/admin_filter_bar.dart';
import 'package:gdc_admin_app/widgets/gdc_popup_menu.dart';

void main() {
  testWidgets('GdcPopupMenuButton.icon opens menu and triggers selection',
      (tester) async {
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GdcPopupMenuButton<String>.icon(
              tooltip: 'Actions',
              menuTitle: 'Staff Actions',
              activeBadgeCount: 2,
              isActive: true,
              onSelected: (value) => selected = value,
              options: const [
                GdcPopupOption<String>(
                  value: 'edit',
                  label: 'Edit Role',
                  subtitle: 'Change permissions',
                  icon: Icons.badge_outlined,
                  isSelected: true,
                ),
                GdcPopupOption<String>(
                  value: 'revoke',
                  label: 'Revoke Access',
                  icon: Icons.block_rounded,
                  isDestructive: true,
                  showDividerBefore: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byType(GdcPopupIconTrigger));
    await tester.pumpAndSettle();

    expect(find.text('STAFF ACTIONS'), findsOneWidget);
    expect(find.text('Edit Role'), findsOneWidget);
    expect(find.text('Change permissions'), findsOneWidget);
    expect(find.text('Revoke Access'), findsOneWidget);

    await tester.tap(find.text('Revoke Access'));
    await tester.pumpAndSettle();

    expect(selected, 'revoke');
  });

  testWidgets('GdcPopupMenuButton.pill displays label, badge, and selects item',
      (tester) async {
    int? chosenDays;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GdcPopupMenuButton<int>.pill(
              label: 'Set All Expiry',
              icon: Icons.event_available_rounded,
              menuTitle: 'Bulk Expiry Preset',
              emphasized: true,
              onSelected: (days) => chosenDays = days,
              options: const [
                GdcPopupOption<int>(
                  value: 90,
                  label: 'Set All: +90 Days',
                  subtitle: '3 months from today',
                  trailingBadge: '3M',
                  icon: Icons.schedule_rounded,
                ),
                GdcPopupOption<int>(
                  value: 365,
                  label: 'Set All: +1 Year',
                  trailingBadge: '1Y',
                  icon: Icons.event_repeat_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Set All Expiry'), findsOneWidget);

    await tester.tap(find.text('Set All Expiry'));
    await tester.pumpAndSettle();

    expect(find.text('BULK EXPIRY PRESET'), findsOneWidget);
    expect(find.text('3M'), findsOneWidget);
    expect(find.text('1Y'), findsOneWidget);

    await tester.tap(find.text('Set All: +90 Days'));
    await tester.pumpAndSettle();

    expect(chosenDays, 90);
  });

  testWidgets('AdminFilterBar exclusion popup toggles state live inside menu',
      (tester) async {
    Map<String, bool> latestExclusions = {'Hide Zero Stock': false};
    AdminDateFilter currentDateFilter = AdminDateFilter.all;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return AdminFilterBar(
                totalCount: 10,
                filteredCount: 10,
                searchQuery: '',
                onSearchChanged: (_) {},
                filterOutOptions: latestExclusions,
                onFilterOutChanged: (updated) {
                  setState(() {
                    latestExclusions = Map<String, bool>.from(updated);
                  });
                },
                dateFilter: currentDateFilter,
                onDateFilterChanged: (f) {
                  setState(() => currentDateFilter = f);
                },
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Filter Out'));
    await tester.pumpAndSettle();

    expect(find.text('EXCLUDE FROM VIEW'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);

    await tester.tap(find.text('Hide Zero Stock'));
    await tester.pumpAndSettle();

    expect(latestExclusions['Hide Zero Stock'], isTrue);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
