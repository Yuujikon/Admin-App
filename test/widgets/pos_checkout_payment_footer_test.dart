import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdc_admin_app/screens/pos_screen.dart';
import 'package:gdc_admin_app/utils/format.dart';
import 'package:gdc_admin_app/utils/pricing_engine.dart';

void main() {
  Widget buildHarness({
    required TextEditingController cashCtrl,
    required FocusNode cashFocus,
    required PricingBreakdown breakdown,
    int totalUnits = 2,
    double? nextBill = 100.0,
    VoidCallback? onComplete,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            final double cashNum = double.tryParse(cashCtrl.text) ?? 0;
            final double change =
                (cashNum - breakdown.total).clamp(0, double.infinity);
            final bool canComplete = cashCtrl.text.trim().isNotEmpty &&
                cashNum >= breakdown.total &&
                breakdown.total > 0;
            return Align(
              alignment: Alignment.bottomCenter,
              child: PosCheckoutPaymentFooter(
                breakdown: breakdown,
                totalUnits: totalUnits,
                cashCtrl: cashCtrl,
                cashFocus: cashFocus,
                cashNum: cashNum,
                change: change,
                nextBill: nextBill,
                canComplete: canComplete,
                isBusy: false,
                onComplete: onComplete ?? () {},
              ),
            );
          },
        ),
      ),
    );
  }

  group('PosCheckoutPaymentFooter — Total -> Cash Received -> Change UI', () {
    testWidgets(
      'hides Change and Insufficient Cash before Cash Received is entered',
      (tester) async {
        final cashCtrl = TextEditingController();
        final cashFocus = FocusNode();
        addTearDown(() {
          cashCtrl.dispose();
          cashFocus.dispose();
        });

        await tester.pumpWidget(
          buildHarness(
            cashCtrl: cashCtrl,
            cashFocus: cashFocus,
            breakdown: const PricingBreakdown(
              subtotal: 58.0,
              vAtAmount: 0,
              total: 58.0,
            ),
          ),
        );

        expect(find.text('Total Cost'), findsOneWidget);
        expect(find.text(formatPeso(58.0)), findsOneWidget);
        expect(find.text('Cash Received'), findsOneWidget);
        expect(find.text('Change'), findsNothing);
        expect(find.text('Insufficient Cash'), findsNothing);
      },
    );

    testWidgets(
      'displays Total Cost -> Cash Received -> Change in strict vertical order once cash is entered',
      (tester) async {
        final cashCtrl = TextEditingController(text: '100');
        final cashFocus = FocusNode();
        addTearDown(() {
          cashCtrl.dispose();
          cashFocus.dispose();
        });

        await tester.pumpWidget(
          buildHarness(
            cashCtrl: cashCtrl,
            cashFocus: cashFocus,
            breakdown: const PricingBreakdown(
              subtotal: 58.0,
              vAtAmount: 0,
              total: 58.0,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final totalFinder = find.text('Total Cost');
        final cashFinder = find.text('Cash Received');
        final changeFinder = find.text('Change');

        expect(totalFinder, findsOneWidget);
        expect(cashFinder, findsOneWidget);
        expect(changeFinder, findsOneWidget);
        expect(find.text(formatPeso(58.0)), findsOneWidget);
        expect(find.text(formatPeso(100.0)), findsOneWidget);
        expect(find.text(formatPeso(42.0)), findsOneWidget);

        // Verify exact visual order: Total -> Cash Received -> Change
        final double totalY = tester.getTopLeft(totalFinder).dy;
        final double cashY = tester.getTopLeft(cashFinder).dy;
        final double changeY = tester.getTopLeft(changeFinder).dy;

        expect(totalY, lessThan(cashY));
        expect(cashY, lessThan(changeY));
      },
    );

    testWidgets(
      'displays Insufficient Cash with Short amount when inputted cash is below Total Cost',
      (tester) async {
        final cashCtrl = TextEditingController(text: '50');
        final cashFocus = FocusNode();
        addTearDown(() {
          cashCtrl.dispose();
          cashFocus.dispose();
        });

        await tester.pumpWidget(
          buildHarness(
            cashCtrl: cashCtrl,
            cashFocus: cashFocus,
            breakdown: const PricingBreakdown(
              subtotal: 58.0,
              vAtAmount: 0,
              total: 58.0,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Total Cost'), findsOneWidget);
        expect(find.text('Cash Received'), findsOneWidget);
        expect(find.text(formatPeso(50.0)), findsOneWidget);
        expect(find.text('Insufficient Cash'), findsOneWidget);
        expect(find.text('Short ${formatPeso(8.0)}'), findsOneWidget);
        expect(find.text('Change'), findsNothing);
      },
    );

    testWidgets(
      'renders cleanly as a right-side panel beside picked items on the left',
      (tester) async {
        final cashCtrl = TextEditingController(text: '100');
        final cashFocus = FocusNode();
        addTearDown(() {
          cashCtrl.dispose();
          cashFocus.dispose();
        });

        await tester.binding.setSurfaceSize(const Size(900, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('555 Sardines'),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 360,
                    child: PosCheckoutPaymentFooter(
                      breakdown: const PricingBreakdown(
                        subtotal: 58.0,
                        vAtAmount: 0,
                        total: 58.0,
                      ),
                      totalUnits: 2,
                      cashCtrl: cashCtrl,
                      cashFocus: cashFocus,
                      cashNum: 100.0,
                      change: 42.0,
                      nextBill: 100.0,
                      isSidePanel: true,
                      canComplete: true,
                      isBusy: false,
                      onComplete: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final double itemX = tester.getTopLeft(find.text('555 Sardines')).dx;
        final double totalX = tester.getTopLeft(find.text('Total Cost')).dx;
        expect(itemX, lessThan(totalX));
        expect(find.text('Cash Received'), findsOneWidget);
        expect(find.text('Change'), findsOneWidget);
      },
    );
  });
}
