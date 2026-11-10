import 'dart:io';

import 'package:cmdline/cmdline.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Starts [handler] and logs the lines from [banner], given the base URL,
/// with `cmdline`'s `trace`, then a `pass` line once it is listening.
///
/// [host] defaults to every IPv4 address. [port] defaults to the `PORT`
/// environment variable, then 8080. The other options are passed to
/// `shelf_io.serve`; [idleTimeout] is set on the returned server.
Future<HttpServer> startServer(
  Handler handler, {
  required List<String> Function(String base) banner,
  Object? host,
  int? port,
  SecurityContext? securityContext,
  int? backlog,
  bool shared = false,
  String? poweredByHeader = 'Dart with package:shelf',
  Duration? idleTimeout,
  bool showBanner = true,
}) async {
  final server = await shelf_io.serve(
    handler,
    host ?? InternetAddress.anyIPv4,
    port ?? int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080,
    securityContext: securityContext,
    backlog: backlog,
    shared: shared,
    poweredByHeader: poweredByHeader,
  );
  if (idleTimeout != null) server.idleTimeout = idleTimeout;

  if (showBanner) {
    final scheme = securityContext == null ? 'http' : 'https';
    final base = '$scheme://localhost:${server.port}';
    banner(base).forEach(trace);
    pass('Listening on port ${server.port}');
  }

  return server;
}
