/// Build HTTP APIs as a tree of routes, with typed params, JSON, errors and
/// OpenAPI docs handled for you.
///
/// An API is a [Server] holding [Route]s, and each route holds the
/// [Endpoint]s (HTTP methods) it answers. Routes nest, so `/todos/<id>` can
/// live inside `/todos` and inherit its params.
///
/// ```dart
/// import 'package:server_sdk/server_sdk.dart';
///
/// Future<void> main() async {
///   final api = Server(
///     name: 'hello',
///     version: '1.0.0',
///     routes: [
///       Route(
///         '/hello',
///         endpoints: [
///           Endpoint.get(
///             query: [const QueryParam.string('name', defaultValue: 'world')],
///             run: (input) => {'message': 'Hello, ${input.query['name']}!'},
///           ),
///         ],
///       ),
///     ],
///   );
///
///   await api.serve(); // http://localhost:8080/hello?name=Dart
/// }
/// ```
///
/// What you get without writing it yourself:
/// * Values declared as [PathParam]s, [QueryParam]s and [BodyField]s are
///   checked and converted before `run` is called. Bad input answers 400.
/// * Whatever `run` returns is sent as JSON. Throw an [ApiError] to answer
///   with an error status.
/// * `/health`, `/version`, `/openapi.json` and a Swagger UI page at
///   `/docs`, each movable or switchable off.
/// * Errors, startup and request logs ([Server.logRequests]) printed with
///   `cmdline`; [Server.onError] and [Server.errorBody] change the answers.
/// * A [Website] (static files, or a [FlutterProject] built for you) served
///   on the same origin as the API.
///
/// A few shelf types are re-exported ([Request], [Response], [Handler],
/// [Middleware] and [logRequests]), so most apps only need this import.
library;

export 'package:shelf/shelf.dart'
    show Handler, Request, Response, Middleware, logRequests;

export 'server.dart';
export 'src/endpoint.dart';
export 'src/errors.dart';
export 'src/flutter_project.dart';
export 'src/input.dart';
export 'src/params.dart';
export 'src/route.dart';
export 'src/router.dart' show CompiledEndpoint;
export 'website.dart';
