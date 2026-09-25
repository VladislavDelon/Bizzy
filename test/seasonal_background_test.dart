import 'package:bizzy_app/web/seasonal_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seasonOf maps months to seasons', () {
    expect(seasonOf(DateTime(2026, 1)), Season.winter);
    expect(seasonOf(DateTime(2026, 2)), Season.winter);
    expect(seasonOf(DateTime(2026, 12)), Season.winter);
    expect(seasonOf(DateTime(2026, 3)), Season.spring);
    expect(seasonOf(DateTime(2026, 5)), Season.spring);
    expect(seasonOf(DateTime(2026, 6)), Season.summer);
    expect(seasonOf(DateTime(2026, 8)), Season.summer);
    expect(seasonOf(DateTime(2026, 9)), Season.autumn);
    expect(seasonOf(DateTime(2026, 11)), Season.autumn);
  });

  testWidgets('seasonal backdrop renders child behind animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SeasonalBackdrop(child: Center(child: Text('контент'))),
      ),
    );
    // Анимация бесконечная — pump кадры вручную, settle не ждём.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('контент'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
