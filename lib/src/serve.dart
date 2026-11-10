import 'dart:io';

import 'package:cmdline/cmdline.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Starts [handler] and prints the lines from [banner] with the base URL.
///
/// [port] defaults to the `PORT` environment variable, then 8080.
Future<HttpServer> startServer(
  Handler handler, {
  required List<String> Function(String base) banner,
  Object? host,
  int? port,
}) async {
  final server = await shelf_io.serve(
    handler,
    host ?? InternetAddress.anyIPv4,
    port ?? int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080,
  );
  banner('http://localhost:${server.port}').forEach(trace);

  return server;
}
