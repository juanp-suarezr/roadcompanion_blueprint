import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/core/widgets/estela_logo.dart';

void main() {
  group('EstelaLogo - Componente oficial de identidad visual', () {
    testWidgets('Renderiza variante emblem sin texto adicional', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: EstelaLogo(size: 64.0, variant: EstelaLogoVariant.emblem),
            ),
          ),
        ),
      );

      expect(find.byType(EstelaLogo), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('ESTELA'), findsNothing);
    });

    testWidgets('Renderiza variante compact con emblema y texto horizontal', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: EstelaLogo(size: 48.0, variant: EstelaLogoVariant.compact),
            ),
          ),
        ),
      );

      expect(find.byType(EstelaLogo), findsOneWidget);
      expect(find.text('REstelar'), findsOneWidget);
      expect(find.text('NAVEGADOR COMPLEMENTARIO'), findsOneWidget);
    });

    testWidgets(
      'Renderiza variante full con emblema, texto y descriptor completo',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(
                child: EstelaLogo(size: 80.0, variant: EstelaLogoVariant.full),
              ),
            ),
          ),
        );

        expect(find.byType(EstelaLogo), findsOneWidget);
        expect(find.text('REstelar'), findsOneWidget);
        expect(find.text('NAVEGADOR DE RUTA COMPLEMENTARIO'), findsOneWidget);
      },
    );

    testWidgets('Renderiza versión monocromática sin excepciones', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: EstelaLogo(
                size: 56.0,
                variant: EstelaLogoVariant.emblem,
                isMonochrome: true,
                customColor: Colors.white,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(EstelaLogo), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
