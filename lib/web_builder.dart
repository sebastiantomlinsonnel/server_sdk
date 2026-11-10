/// Build HTTP APIs as a tree of routes, the way `cmdline` builds CLIs.
///
/// Declare [WEB] → [Route] → [Endpoint], with typed [PathParam]s,
/// [QueryParam]s and [BodyField]s. Validation, JSON, errors and OpenAPI docs
/// are handled for you. Give [WEB] a [FlutterProject] to serve (and build)
/// a Flutter site next to the API.
library;

export 'package:shelf/shelf.dart'
    show Handler, Request, Response, Middleware, logRequests;

export 'src/endpoint.dart';
export 'src/errors.dart';
export 'src/input.dart';
export 'src/params.dart';
export 'src/route.dart';
export 'src/router.dart' show CompiledEndpoint;
export 'src/flutter_project.dart';
export 'src/website.dart';
export 'web.dart';
