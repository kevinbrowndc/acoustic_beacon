import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:acoustic_beacon/presentation/app.dart';

void main() {
  testWidgets('onboarding explains control before requesting microphone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      BeaconApp(preferences: await SharedPreferences.getInstance()),
    );
    expect(find.text('Discover what’s around you.'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Designed with privacy in mind.'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('You’re in control.'), findsOneWidget);
    await tester.ensureVisible(find.text('Not now'));
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Listening is off'), findsOneWidget);
    expect(find.text('Beacon Detected'), findsNothing);
    await tester.tap(find.text('Near You'));
    await tester.pumpAndSettle();
    expect(find.text('Nearby locations'), findsOneWidget);
    expect(find.text('Beacon Detected'), findsNothing);
  });
  testWidgets('consumer navigation works with large text and dark theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({
      'onboarded': true,
      'theme': 'dark',
    });
    await tester.pumpWidget(
      BeaconApp(preferences: await SharedPreferences.getInstance()),
    );
    for (final title in ['Saved', 'Settings', 'Detected']) {
      await tester.tap(find.widgetWithText(NavigationDestination, title));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
