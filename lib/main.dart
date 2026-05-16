// lib/main.dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/db/app_database.dart';
import 'data/db/seed.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, 'highbrid_pos.sqlite'));
  final db = AppDatabase(NativeDatabase(file));
  await seedIfEmpty(db);

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const HighbridPosApp(),
    ),
  );
}
