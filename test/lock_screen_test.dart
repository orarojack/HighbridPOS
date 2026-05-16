// test/lock_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';
import 'package:highbrid_pos/data/db/seed.dart';
import 'package:highbrid_pos/features/auth/auth_controller.dart';
import 'package:highbrid_pos/features/auth/lock_screen.dart';
import 'package:highbrid_pos/features/home_shell.dart';
import 'package:highbrid_pos/providers.dart';

/// HighbridPOS is a desktop POS terminal; widen the test surface so the
/// NavigationRail layout fits.
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

/// Logs CSH-001 in (clearing the seeded forced-PIN-change flag) so the home
/// shell can be exercised directly.
Future<void> _signInCashier(ProviderContainer container) async {
  final result = await container
      .read(authControllerProvider.notifier)
      .loginWithPin('CSH-001', '000000');
  // CSH-001 ships with a new PIN; change it so forcePinChange clears.
  await container
      .read(authRepositoryProvider)
      .changePin(result.user!.id, '111111');
  container.read(authControllerProvider.notifier).clearForcePinChange();
}

Future<void> _pumpShell(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: HomeShell()),
  ));
  await tester.pumpAndSettle();
}

/// The shell pages underneath the lock overlay also contain TextFields, so
/// scope re-entry input to fields inside the [LockScreen] itself.
Finder _lockField(int index) => find
    .descendant(of: find.byType(LockScreen), matching: find.byType(TextField))
    .at(index);

/// Locks the shell and enters [staffId] + [pin] into the lock screen, then
/// taps Unlock.
Future<void> _attemptUnlock(
  WidgetTester tester,
  String staffId,
  String pin,
) async {
  await tester.enterText(_lockField(0), staffId);
  await tester.enterText(_lockField(1), pin);
  await tester.tap(find.text('Unlock'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tapping Lock shows the lock screen without logging out',
      (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer();
    addTearDown(container.dispose);
    await _signInCashier(container);

    await _pumpShell(tester, container);
    expect(find.byType(LockScreen), findsNothing);

    await tester.tap(find.text('Lock'));
    await tester.pumpAndSettle();

    expect(find.byType(LockScreen), findsOneWidget);
    // Identity is retained — the user is NOT logged out.
    expect(container.read(authControllerProvider)?.username, 'cashier');
  });

  testWidgets('wrong PIN keeps the lock screen and shows an inline error',
      (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer();
    addTearDown(container.dispose);
    await _signInCashier(container);

    await _pumpShell(tester, container);
    await tester.tap(find.text('Lock'));
    await tester.pumpAndSettle();

    await _attemptUnlock(tester, 'CSH-001', '999999');

    expect(find.text('Incorrect Staff ID or PIN.'), findsOneWidget);
    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('a different valid account cannot bypass the lock',
      (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer();
    addTearDown(container.dispose);
    await _signInCashier(container);

    await _pumpShell(tester, container);
    await tester.tap(find.text('Lock'));
    await tester.pumpAndSettle();

    // ADM-001 is a valid account, but not the locked (cashier) user.
    await _attemptUnlock(tester, 'ADM-001', '000000');

    expect(find.text('These credentials are not for the locked account.'),
        findsOneWidget);
    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('correct PIN re-entry dismisses the lock screen',
      (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer();
    addTearDown(container.dispose);
    await _signInCashier(container);

    await _pumpShell(tester, container);
    await tester.tap(find.text('Lock'));
    await tester.pumpAndSettle();

    await _attemptUnlock(tester, 'CSH-001', '111111');

    expect(find.byType(LockScreen), findsNothing);
    expect(container.read(authControllerProvider)?.username, 'cashier');
  });
}
