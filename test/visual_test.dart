import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:acoustic_beacon/presentation/app.dart';
import 'package:acoustic_beacon/application/beacon_controller.dart';
import 'package:acoustic_beacon/data/content.dart';
import 'package:acoustic_beacon/protocol/beacon_protocol.dart';
import 'controller_test.dart' show TestCapture;

void main() {
  setUpAll(() async {
    final config =
        jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
            as Map<String, dynamic>;
    final packages = config['packages'] as List;
    final flutter = packages.cast<Map<String, dynamic>>().firstWhere(
      (e) => e['name'] == 'flutter',
    );
    final sdk = Directory.fromUri(
      Uri.parse(flutter['rootUri'] as String),
    ).parent.parent;
    for (final pair in [
      ('Ahem', 'roboto-regular.ttf'),
      ('Roboto', 'roboto-regular.ttf'),
      ('MaterialIcons', 'materialicons-regular.otf'),
    ]) {
      final loader = FontLoader(pair.$1)
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '${sdk.path}/bin/cache/artifacts/material_fonts/${pair.$2}',
              ).readAsBytesSync(),
            ),
          ),
        );
      await loader.load();
    }
  });
  for (final theme in ['light', 'dark']) {
    testWidgets('validated and saved content $theme', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'onboarded': true,
        'theme': theme,
      });
      final preferences = await SharedPreferences.getInstance();
      final capture = TestCapture();
      final controller = BeaconController(capture, LocalContentRepository());
      await tester.pumpWidget(
        BeaconApp(preferences: preferences, controller: controller),
      );
      await controller.start();
      await tester.pump(const Duration(milliseconds: 200));
      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/$theme-Listening.png'),
      );
      capture.stream.add(
        synthesize(
          const BeaconConfig(),
          ExperimentalCodec().encode('wookiemeat'),
          repetitions: 2,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Beacon Detected'), findsOneWidget);
      // Freeze only display time so screenshots are reproducible; validation above used the full DSP path.
      controller.lastDetection = DateTime(2026, 9, 22, 12);
      controller.notifyListeners();
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/$theme-Validated.png'),
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(preferences.getStringList('saved'), hasLength(1));
      await tester.tap(find.widgetWithText(NavigationDestination, 'Saved'));
      await tester.pumpAndSettle();
      expect(find.text('Beacon Detected'), findsOneWidget);
      await tester.runAsync(controller.stop);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets('screen review $theme', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'onboarded': true,
        'theme': theme,
      });
      await tester.pumpWidget(
        BeaconApp(preferences: await SharedPreferences.getInstance()),
      );
      await tester.pumpAndSettle();
      for (final title in ['Detected', 'Near You', 'Saved', 'Settings']) {
        await tester.tap(find.widgetWithText(NavigationDestination, title));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile('goldens/$theme-${title.replaceAll(' ', '-')}.png'),
        );
      }
    });
  }
}
