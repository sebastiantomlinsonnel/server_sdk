// Serves a folder of static files next to an API.
//
// Put an `index.html` in `public/`, then run
// `dart run example/static_site.dart`.
import 'package:server_sdk/server_sdk.dart';

Future<void> main() async {
  final server = Server(
    name: 'site',
    prefix: '/api',
    docs: false,
    // No /api/openapi.json or /api/docs.
    routes: [
      Route(
        '/contact',
        endpoints: [
          Endpoint.post(
            body: [
              const BodyField.string('email', required: true),
              const BodyField.string('message', required: true),
            ],
            run: (input) {
              final email = input.body.get<String>('email');
              if (!email.contains('@')) {
                throw const ApiError.badRequest('email is not valid');
              }

              // Save or send the message here.
              return {'received': true};
            },
          ),
        ],
      ),
    ],
    website: StaticWebsite(
      'public',
      // Send index.html for unknown pages, for apps with their own routing.
      spaFallback: true,
      cacheControl: 'max-age=300',
    ),
  );

  await server.serve(port: 3000);
}
