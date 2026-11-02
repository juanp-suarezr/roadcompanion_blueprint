import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/core/services/app_build_info_service.dart';
import 'package:road_companion/core/widgets/app_build_info_widget.dart';

void main() {
  tearDown(() {
    AppBuildInfoService.resetCache();
  });

  testWidgets(
    'AppBuildInfoWidget renders formatted text when info is available',
    (WidgetTester tester) async {
      final fixedTime = DateTime(2026, 11, 1, 20, 33);
      AppBuildInfoService.setMockInfo(
        AppBuildInfo(buildTime: fixedTime, buildMode: 'RELEASE'),
      );

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppBuildInfoWidget())),
      );

      await tester.pump();

      expect(
        find.text('Última actualización: 01 nov 2026 · 20:33 · RELEASE'),
        findsOneWidget,
      );
    },
  );

  testWidgets('AppBuildInfoWidget respects alignment parameter', (
    WidgetTester tester,
  ) async {
    AppBuildInfoService.setMockInfo(
      const AppBuildInfo(buildTime: null, buildMode: 'DEBUG'),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppBuildInfoWidget(textAlign: TextAlign.start)),
      ),
    );

    await tester.pump();

    final textWidget = tester.widget<Text>(find.byType(Text));
    expect(textWidget.textAlign, equals(TextAlign.start));
    expect(textWidget.data, equals('Modo DEBUG'));
  });
}
