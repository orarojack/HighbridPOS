// lib/data/db/connection/connection_web.dart
//
// Web (WebAssembly) database connection.
//
// Opens the application database on top of a drift `WasmDatabase`, which runs
// SQLite compiled to WebAssembly inside the browser. `WasmDatabase.open`
// automatically picks the best available persistent storage (OPFS-backed in
// a worker, or IndexedDB) so data survives a page refresh; if no persistent
// option is available it transparently falls back to an in-memory database.
import 'package:drift/wasm.dart';

import '../app_database.dart';

/// Opens the application database backed by SQLite-on-WebAssembly.
///
/// `sqlite3.wasm` and `drift_worker.js` must be present in the `web/` folder
/// (they are copied verbatim into the build output by `flutter build web`).
Future<AppDatabase> openAppDatabase() async {
  final result = await WasmDatabase.open(
    databaseName: 'highbrid_pos',
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );

  return AppDatabase(result.resolvedExecutor);
}
