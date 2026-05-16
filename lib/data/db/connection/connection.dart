// lib/data/db/connection/connection.dart
//
// Cross-platform entrypoint for opening the application database.
//
// The actual implementation is selected at compile time:
//   * native (Linux desktop, tests) -> connection_native.dart
//   * web (WebAssembly)             -> connection_web.dart
//
// Both implementations expose `Future<AppDatabase> openAppDatabase()`.
export 'connection_native.dart'
    if (dart.library.js_interop) 'connection_web.dart';
