import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photomailer/core/constants.dart';
import 'package:photomailer/features/send/send_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSendScreen(
    WidgetTester tester, {
    required Size surfaceSize,
  }) async {
    const permissionChannel =
        MethodChannel('flutter.baseflow.com/permissions/methods');
    const nativeChannel = MethodChannel(AppConstants.nativeChannelName);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(surfaceSize);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      permissionChannel,
      (call) async {
        switch (call.method) {
          case 'checkPermissionStatus':
          case 'checkServiceStatus':
            return 1;
          case 'requestPermissions':
            return <int, int>{33: 1};
          case 'shouldShowRequestPermissionRationale':
            return false;
          case 'openAppSettings':
            return true;
          default:
            return 1;
        }
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      nativeChannel,
      (call) async => null,
    );
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(permissionChannel, null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, null);
    });
    await tester.pumpWidget(const MaterialApp(home: SendScreen()));

    final menuFinder = find.byKey(const ValueKey('step-menu-container'));
    for (var i = 0; i < 60; i++) {
      if (menuFinder.evaluate().isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(menuFinder, findsOneWidget);
  }

  testWidgets(
      'phone layout shows labels first and collapses into icon row on scroll',
      (tester) async {
    await pumpSendScreen(tester, surfaceSize: const Size(390, 460));

    final menuFinder = find.byKey(const ValueKey('step-menu-container'));
    final scrollFinder =
        find.byKey(const ValueKey('step-scroll-messageParams'));
    expect(menuFinder, findsOneWidget);

    await tester.drag(scrollFinder, const Offset(0, 280));
    await tester.pump(const Duration(milliseconds: 250));
    final expandedHeight = tester.getSize(menuFinder).height;

    await tester.drag(scrollFinder, const Offset(0, -420));
    await tester.pump(const Duration(milliseconds: 350));
    final collapsedHeight = tester.getSize(menuFinder).height;

    expect(collapsedHeight, lessThan(expandedHeight));
    expect(
      find.byKey(const ValueKey('step-icon-messageParams')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('step-icon-pickAndPhotos')),
      findsOneWidget,
    );
  }, skip: true);

  testWidgets(
      'tablet layout shows one-row labels first and collapses into icon row on scroll',
      (tester) async {
    await pumpSendScreen(tester, surfaceSize: const Size(820, 460));

    final menuFinder = find.byKey(const ValueKey('step-menu-container'));
    final scrollFinder =
        find.byKey(const ValueKey('step-scroll-messageParams'));
    expect(menuFinder, findsOneWidget);

    await tester.drag(scrollFinder, const Offset(0, 280));
    await tester.pump(const Duration(milliseconds: 250));
    final expandedHeight = tester.getSize(menuFinder).height;

    await tester.drag(scrollFinder, const Offset(0, -420));
    await tester.pump(const Duration(milliseconds: 350));
    final collapsedHeight = tester.getSize(menuFinder).height;

    expect(collapsedHeight, lessThan(expandedHeight));
    expect(
      find.byKey(const ValueKey('step-icon-messageParams')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('step-icon-analytics')),
      findsOneWidget,
    );
  }, skip: true);
}
