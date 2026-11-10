// Serves a Flutter web app and an API from one server, on one origin.
//
// Expects a Flutter project in `../my_app` (next to this server). Run with
// `dart run example/flutter_app.dart`:
//
// * http://localhost:8080/          the Flutter app
// * http://localhost:8080/api/time  the API
// * http://localhost:8080/api/docs  the API docs
//
// The app can call the API with a relative URL like `/api/time`, so there is
// no CORS to set up.
import 'dart:io';

import 'package:server_sdk/server_sdk.dart';

Future<void> main() async {
  // Build locally when sources change; on a server, ship a prebuilt
  // `build/web` and never build.
  final isProduction = Platform.environment['ENV'] == 'production';

  final server = WEB(
    name: 'my app',
    version: '1.0.0',
    // With a website, API paths need a prefix to tell them apart.
    prefix: '/api',
    middleware: [logRequests()],
    routes: [
      Route(
        '/time',
        endpoints: [
          Endpoint.get(
            help: 'The server time',
            run: (_) => {'now': DateTime.now().toIso8601String()},
          ),
        ],
      ),
    ],
    website: FlutterProject(
      '../my_app',
      build: isProduction ? FlutterBuild.never : FlutterBuild.ifChanged,
      dartDefines: {'API_BASE': '/api'},
      buildArgs: ['--release'],
      // Rebuild when a shared package changes too.
      watch: ['../shared'],
    ),
  );

  try {
    await server.serve();
  } on FlutterBuildException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
