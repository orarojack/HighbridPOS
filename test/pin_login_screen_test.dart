// test/pin_login_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/app.dart';
import 'package:highbrid_pos/data/db/app_database.dart';
import 'package:highbrid_pos/data/db/seed.dart';
import 'package:highbrid_pos/features/auth/auth_controller.dart';
import 'package:highbrid_pos/features/auth/login_screen.dart';
import 'package:highbrid_pos/features/auth/pin_change_screen.dart';
import 'package:highbrid_pos/features/home_shell.dart';
import 'package:highbrid_pos/providers.dart';

/// HighbridPOS is a desktop POS terminal; the home shell uses a wide
/// NavigationRail layout. Widen the test surface so routed-to screens lay
/// out, and reset it afterwards.
void _useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<ProviderContainer> _seededContainer() async {
  final db = AppDatabase(NativeDatabase.memory());
  await seedIfEmpty(db);
  return ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db)],
  );
}

/// Enters [staffId] and [pin] into the Staff PIN fields and taps Sign in.
Future<void> _signInWithPin(
  WidgetTester tester,
  String staffId,
  String pin,
) async {
  await tester.enterText(find.byType(TextField).first, staffId);
  await tester.enterText(find.byType(TextField).last, pin);
  await tester.tap(find.text('Sign in'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('PIN login success with CSH-001 / 000000 routes onward',
      (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const HighbridPosApp(),
    ));
    await tester.pumpAndSettle();

    await _signInWithPin(tester, 'CSH-001', '000000');

    // CSH-001 is seeded with forcePinChange: true, so a successful PIN login
    // routes onward to the PIN-change screen rather than staying on login.
    expect(container.read(authControllerProvider)?.username, 'cashier');
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(PinChangeScreen), findsOneWidget);
  });

  testWidgets('wrong PIN shows an inline error', (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const HighbridPosApp(),
    ));
    await tester.pumpAndSettle();

    await _signInWithPin(tester, 'CSH-001', '999999');

    expect(find.text('Incorrect Staff ID or PIN.'), findsOneWidget);
    expect(container.read(authControllerProvider), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('5 wrong PINs then a correct one shows the locked message',
      (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const HighbridPosApp(),
    ));
    await tester.pumpAndSettle();

    // Five consecutive wrong PINs trigger the lockout.
    for (var i = 0; i < 5; i++) {
      await _signInWithPin(tester, 'CSH-001', '999999');
    }

    // Even with the correct PIN, the account is now locked.
    await _signInWithPin(tester, 'CSH-001', '000000');

    expect(find.textContaining('Account locked until'), findsOneWidget);
    expect(container.read(authControllerProvider), isNull);
  });

  testWidgets('a forced-PIN-change user lands on PinChangeScreen',
      (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const HighbridPosApp(),
    ));
    await tester.pumpAndSettle();

    await _signInWithPin(tester, 'CSH-001', '000000');

    expect(find.byType(PinChangeScreen), findsOneWidget);

    // Completing the PIN change routes through to the home shell.
    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Save PIN'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeShell), findsOneWidget);
    expect(container.read(authControllerProvider)?.forcePinChange, false);
  });
}
