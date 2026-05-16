// test/login_screen_test.dart
import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';
import 'package:highbrid_pos/data/db/seed.dart';
import 'package:highbrid_pos/domain/enums.dart';
import 'package:highbrid_pos/features/auth/auth_controller.dart';
import 'package:highbrid_pos/features/auth/login_screen.dart';
import 'package:highbrid_pos/providers.dart';

Future<ProviderContainer> _seededContainer() async {
  final db = AppDatabase(NativeDatabase.memory());
  await seedIfEmpty(db);
  return ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db)],
  );
}

/// The login screen opens in Staff PIN mode; switch it to Manager mode so the
/// username/password fields are shown.
Future<void> _selectManagerMode(WidgetTester tester) async {
  await tester.tap(find.text('Manager'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows an error on a wrong password', (tester) async {
    final container = await _seededContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LoginScreen()),
    ));

    await _selectManagerMode(tester);
    await tester.enterText(find.byType(TextField).first, 'admin');
    await tester.enterText(find.byType(TextField).last, 'nope');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Invalid username'), findsOneWidget);
    expect(container.read(authControllerProvider), isNull);
  });

  testWidgets('logs in with correct credentials', (tester) async {
    final container = await _seededContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LoginScreen()),
    ));

    await _selectManagerMode(tester);
    await tester.enterText(find.byType(TextField).first, 'admin');
    await tester.enterText(find.byType(TextField).last, 'admin123');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(container.read(authControllerProvider)?.username, 'admin');
  });

  testWidgets('rejects an inactive account', (tester) async {
    final container = await _seededContainer();
    addTearDown(container.dispose);

    // Insert an inactive user directly into the in-memory test database
    // so the real seed (seed.dart) is not affected.
    final db = container.read(databaseProvider);
    await db.into(db.users).insert(UsersCompanion.insert(
          username: 'disabled_user',
          passwordHash: BCrypt.hashpw('disabled123', BCrypt.gensalt()),
          fullName: 'Disabled User',
          role: UserRole.admin.name,
          active: const Value(false),
        ));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LoginScreen()),
    ));

    await _selectManagerMode(tester);
    await tester.enterText(find.byType(TextField).first, 'disabled_user');
    await tester.enterText(find.byType(TextField).last, 'disabled123');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(
      find.text('Invalid username or password, or the account is disabled.'),
      findsOneWidget,
    );
    expect(container.read(authControllerProvider), isNull);
  });
}
