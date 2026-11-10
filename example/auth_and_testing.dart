// Shows custom middleware (a simple API key check) and how to call the API
// in tests through `WEB.handler`, without opening a port.
//
// Run with `dart run example/auth_and_testing.dart`.
import 'dart:convert';

import 'package:server_sdk/server_sdk.dart';

/// Rejects requests without the right `x-api-key` header, except health
/// checks.
Middleware requireApiKey(String key) =>
    (inner) => (request) {
      if (request.url.path == 'health' || request.headers['x-api-key'] == key) {
        return inner(request);
      }

      return Response(
        401,
        body: jsonEncode(const ApiError.unauthorized().toJson()),
        headers: {'content-type': 'application/json'},
      );
    };

final api = Server(
  name: 'secret',
  middleware: [requireApiKey('let-me-in')],
  routes: [
    Route(
      '/greet/<name>',
      endpoints: [
        Endpoint.get(
          run: (input) => {'hello': input.params.get<String>('name')},
        ),
      ],
    ),
  ],
);

Future<void> main() async {
  Future<(int, String)> call(
    String path, {
    Map<String, String>? headers,
  }) async {
    final response = await api.handler(
      Request('GET', Uri.parse('http://localhost$path'), headers: headers),
    );

    return (response.statusCode, await response.readAsString());
  }

  print(await call('/health')); // (200, {"status":"ok"})
  print(await call('/greet/dart')); // (401, {"error":"unauthorized"})
  print(
    await call('/greet/dart', headers: {'x-api-key': 'let-me-in'}),
  ); // (200, {"hello":"dart"})
  print(
    await call('/nope', headers: {'x-api-key': 'let-me-in'}),
  ); // (404, {"error":"not found"})
}
