// lib/data/db/connection/connection_native.dart
//
// Native (Linux desktop / VM test) database connection.
//
// Stores the SQLite database as a file in the application support directory
// using a synchronous NativeDatabase. This is the original behaviour that
// previously lived inline in main.dart.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_database.dart';

/// Opens the application database backed by a file on disk.
Future<AppDatabase> openAppDatabase() async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, 'highbrid_pos.sqlite'));
  return AppDatabase(NativeDatabase(file));
}
