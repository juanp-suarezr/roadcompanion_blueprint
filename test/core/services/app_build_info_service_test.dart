import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/core/services/app_build_info_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppBuildInfo formatting', () {
    test('formats valid date and RELEASE mode correctly', () {
      final dt = DateTime(2026, 11, 1, 20, 33);
      final info = AppBuildInfo(buildTime: dt, buildMode: 'RELEASE');

      expect(
        info.formatDisplay(),
        equals('Última actualización: 01 nov 2026 · 20:33 · RELEASE'),
      );
    });

    test(
      'formats valid date and DEBUG mode with single digit day and minute',
      () {
        final dt = DateTime(2026, 5, 4, 8, 5);
        final info = AppBuildInfo(buildTime: dt, buildMode: 'DEBUG');

        expect(
          info.formatDisplay(),
          equals('Última actualización: 04 may 2026 · 08:05 · DEBUG'),
        );
      },
    );

    test('verifies all 12 Spanish month abbreviations', () {
      final monthsExpected = [
        'ene',
        'feb',
        'mar',
        'abr',
        'may',
        'jun',
        'jul',
        'ago',
        'sep',
        'oct',
        'nov',
        'dic',
      ];

      for (int m = 1; m <= 12; m++) {
        final dt = DateTime(2026, m, 15, 12, 0);
        final info = AppBuildInfo(buildTime: dt, buildMode: 'release');
        expect(info.formatDisplay(), contains(monthsExpected[m - 1]));
      }
    });

    test('handles null buildTime gracefully', () {
      const info = AppBuildInfo(buildTime: null, buildMode: 'RELEASE');
      expect(info.formatDisplay(), equals('Modo RELEASE'));
    });
  });

  group('AppBuildInfoService channel handling', () {
    const channelName = 'test_build_controls';
    const channel = MethodChannel(channelName);

    tearDown(() {
      AppBuildInfoService.resetCache();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'extracts timestamp and buildType from native channel response',
      () async {
        final expectedTime = DateTime(2026, 11, 1, 20, 33);
        final millis = expectedTime.millisecondsSinceEpoch;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              if (call.method == 'getAppBuildInfo') {
                return <String, dynamic>{
                  'buildTimestamp': millis,
                  'buildType': 'RELEASE',
                };
              }
              return null;
            });

        final info = await AppBuildInfoService.getBuildInfo(channel: channel);

        expect(info.buildMode, equals('RELEASE'));
        expect(info.buildTime, equals(expectedTime));
        expect(
          info.formatDisplay(),
          equals('Última actualización: 01 nov 2026 · 20:33 · RELEASE'),
        );
      },
    );

    test('handles channel errors without throwing exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            throw PlatformException(
              code: 'UNAVAILABLE',
              message: 'Not implemented',
            );
          });

      final info = await AppBuildInfoService.getBuildInfo(channel: channel);

      expect(info.buildTime, isNull);
      expect(info.buildMode.isNotEmpty, isTrue);
    });
  });
}
