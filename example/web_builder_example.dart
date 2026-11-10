import 'package:server_sdk/server_sdk.dart';

/// Run it, then open http://localhost:8080/docs.
Future<void> main() async {
  final api = WEB(
    name: 'hello',
    version: '1.0.0',
    help: 'Says hello.',
    middleware: [logRequests()],
    routes: [
      Route(
        '/hello',
        help: 'Greetings',
        endpoints: [
          Endpoint.get(
            help: 'Greet someone',
            query: [const QueryParam.string('name', defaultValue: 'world')],
            run: (input) => {'message': 'Hello, ${input.query['name']}!'},
          ),
        ],
        routes: [
          Route(
            '/<times>',
            params: [const PathParam.int('times', help: 'How many hellos')],
            endpoints: [
              Endpoint.get(
                run: (input) => {
                  'message': 'Hello! ' * input.params.get<int>('times'),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  await api.serve();
}
