/// A API along with an optional website
library server;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cmdline/cmdline.dart';
import 'package:shelf/shelf.dart';

import 'src/endpoint.dart';
import 'src/errors.dart';
import 'src/flutter_project.dart';
import 'src/input.dart';
import 'src/openapi.dart';
import 'src/params.dart';
import 'src/route.dart';
import 'src/router.dart';
import 'src/serve.dart';
import 'website.dart';

/// An HTTP API described as a tree of [Route]s.
///
/// Handles the plumbing for you:
/// * Path, query and body values are checked against their declarations;
///   a mistake answers 400 with `{"error": "..."}`.
/// * Unknown paths answer 404, known paths with the wrong method 405.
/// * `run` results are sent as JSON; `null` answers 204.
/// * A thrown [ApiError] answers with its status, shaped by [errorBody];
///   any other exception goes to [onError], which by default logs it with
///   `cmdline` and answers 500.
/// * `GET <prefix>/health`, and `GET <prefix>/version` when [version] is
///   set. Move them with [healthPath] and [versionPath], turn them off with
///   `null`, or declare your own to replace them.
/// * `GET <prefix>/openapi.json` and `GET <prefix>/docs` describe every
///   route, unless [docs] is false. Move them with [openApiPath] and
///   [docsPath].
/// * `HEAD` requests are answered by the matching `GET` endpoint.
/// * With a [website], every path outside [prefix] is served from it, so the
///   site and the API share one origin.
///
/// ```dart
/// final api = Server(
///   name: 'todos',
///   version: '1.0.0',
///   help: 'A small todo list.',
///   prefix: '/api',
///   middleware: [Server.logRequests(), Server.cors()],
///   routes: [
///     Route(
///       '/todos',
///       help: 'Todos',
///       endpoints: [
///         Endpoint.get(run: (_) => todos),
///       ],
///     ),
///   ],
/// );
///
/// await api.serve(port: 3000);
/// ```
class Server {
  /// The name shown in the docs and when the server starts.
  final String name;

  /// The version answered by `/version` and shown in the docs.
  ///
  /// When left out, `/version` isn't available.
  final String? version;

  /// A description shown at the top of the docs.
  final String? help;

  /// A path added in front of every route, like `/api`.
  final String prefix;

  /// Shelf middleware run around every request, API and website alike,
  /// outermost first.
  final List<Middleware> middleware;

  /// The top-level routes.
  final List<Route> routes;

  /// Whether to serve `/openapi.json` and `/docs`.
  final bool docs;

  /// A site served for every path outside [prefix], like a [FlutterProject]
  /// or a [StaticWebsite].
  final Website? website;

  /// Where the health check is served, under [prefix]. `null` turns it off.
  final String? healthPath;

  /// Where the version is served, under [prefix], when [version] is set.
  /// `null` turns it off.
  final String? versionPath;

  /// Where the OpenAPI document is served, under [prefix]. `null` turns it
  /// off, and the [docsPath] page with it.
  final String? openApiPath;

  /// Where the docs page is served, under [prefix]. `null` turns it off.
  final String? docsPath;

  /// Answers any exception that isn't an [ApiError].
  ///
  /// When left out, the error and stack are logged with `cmdline` and the
  /// caller gets 500 with `{"error": "internal error"}`. If [onError] itself
  /// throws, that is logged and the same 500 is sent.
  ///
  /// ```dart
  /// onError: (error, stack, request) {
  ///   reportCrash(error, stack);
  ///   return Response.internalServerError(body: 'Sorry!');
  /// },
  /// ```
  final FutureOr<Response> Function(
    Object error,
    StackTrace stack,
    Request request,
  )?
  onError;

  /// Builds the JSON body for every [ApiError]: thrown by your endpoints,
  /// bad input (400), unknown paths (404) and wrong methods (405).
  ///
  /// The status and the error's headers are kept. Defaults to
  /// [ApiError.toJson], `{"error": message, "details": ...}`.
  ///
  /// ```dart
  /// errorBody: (error) => {'message': error.message, 'code': error.status},
  /// ```
  final Object? Function(ApiError error)? errorBody;

  final Router _router = Router();
  Handler? _handler;

  /// Creates the API. Throws an [ArgumentError] when two endpoints clash, a
  /// [PathParam] isn't in its path, a path uses the same `<name>` twice, or
  /// a [website] is given without a [prefix].
  Server(
    this.name, {
    this.version,
    this.help,
    this.prefix = '',
    this.middleware = const [],
    this.routes = const [],
    this.docs = true,
    this.website,
    this.healthPath = 'health',
    this.versionPath = 'version',
    this.openApiPath = 'openapi.json',
    this.docsPath = 'docs',
    this.onError,
    this.errorBody,
  }) {
    if (website != null && joinPaths('', prefix) == '/') {
      throw ArgumentError(
        'A WEB with a website needs a prefix for its API, like /api',
      );
    }
    for (final route in routes) {
      _router.addRoute(route, prefix: prefix);
    }
    _addBuiltIns();
  }

  /// Every endpoint with its full path, including the built-in ones.
  List<CompiledEndpoint> get endpoints => List.unmodifiable(_router.endpoints);

  /// The OpenAPI 3.1 document for the declared routes.
  Map<String, Object?> get openApi => buildOpenApi(
    title: name,
    version: version,
    description: help,
    endpoints: _router.endpoints.where((e) => !e.builtIn),
  );

  /// The shelf handler for the API and the [website], with [middleware]
  /// applied.
  ///
  /// Use it in tests or to mount the API in another shelf server. Call
  /// `website.prepare()` first if the website may still need building.
  ///
  /// Testing without opening a port:
  ///
  /// ```dart
  /// final response = await api.handler(
  ///   Request('GET', Uri.parse('http://localhost/api/todos')),
  /// );
  /// print(response.statusCode); // 200
  /// print(await response.readAsString());
  /// ```
  Handler get handler => _handler ??= _buildHandler();

  /// Gets the [website] ready (building it when needed), then starts
  /// listening and logs the website, API and docs URLs with `cmdline`.
  ///
  /// * [host] defaults to every IPv4 address (`0.0.0.0`). [port] defaults
  ///   to the `PORT` environment variable, then 8080.
  /// * [securityContext] serves HTTPS instead of HTTP.
  /// * [shared] lets several isolates bind the same [port]; [backlog] is
  ///   the listen queue length.
  /// * [idleTimeout] closes idle keep-alive connections after that long.
  /// * [poweredByHeader] is sent as `x-powered-by`; `null` leaves it out.
  /// * [banner] false starts quietly, without the startup lines.
  ///
  /// Throws a [FlutterBuildException] when a [FlutterProject] fails to
  /// build, and a [StateError] when the website's folder doesn't exist.
  Future<HttpServer> serve({
    Object? host,
    int? port,
    SecurityContext? securityContext,
    bool shared = false,
    int? backlog,
    Duration? idleTimeout,
    String? poweredByHeader = 'Dart with package:shelf',
    bool banner = true,
  }) async {
    await website?.prepare();
    final prefix = joinPaths('', this.prefix);
    final docsUrl = _docsUrl;

    return startServer(
      handler, // Built before binding, so a missing website fails early.
      host: host,
      port: port,
      securityContext: securityContext,
      shared: shared,
      backlog: backlog,
      idleTimeout: idleTimeout,
      poweredByHeader: poweredByHeader,
      showBanner: banner,
      banner: (base) => [
        if (website != null) 'Website at $base/',
        'API $name${version == null ? '' : ' $version'} '
            'at $base${prefix == '/' ? '' : prefix}',
        if (docsUrl != null) 'Docs at $base$docsUrl',
      ],
    );
  }

  /// Middleware that logs every request with `cmdline`, like
  /// `GET /api/todos?done=false 200 3ms`.
  ///
  /// The level follows the answer: `log` for success and redirects, `warn`
  /// for 4xx, and `fail` for 5xx and for errors thrown past the API (like a
  /// failing website).
  ///
  /// ```dart
  /// Server(
  ///   name: 'api',
  ///   middleware: [Server.logRequests()],
  ///   routes: [...],
  /// );
  /// ```
  static Middleware logRequests() =>
      (inner) => (request) async {
        final watch = Stopwatch()..start();
        final query = request.url.hasQuery ? '?${request.url.query}' : '';
        final line = '${request.method} /${request.url.path}$query';
        String took() => '${watch.elapsedMilliseconds}ms';

        try {
          final response = await inner(request);
          final status = response.statusCode;
          final message = '$line $status ${took()}';
          if (status >= 500) {
            fail(message);
          } else if (status >= 400) {
            warn(message);
          } else {
            log(message);
          }

          return response;
        } on HijackException {
          rethrow;
        } catch (error) {
          fail('$line threw after ${took()}: $error');
          rethrow;
        }
      };

  /// Middleware that lets browsers on other origins call the API, and answers
  /// `OPTIONS` preflight requests.
  ///
  /// [origin] is sent as `access-control-allow-origin`; the default `*`
  /// allows any site. [methods] and [headers] list what callers may use.
  ///
  /// ```dart
  /// Server(
  ///   name: 'api',
  ///   middleware: [Server.cors(origin: 'https://example.com')],
  ///   routes: [...],
  /// );
  /// ```
  static Middleware cors({
    String origin = '*',
    List<String> methods = const ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
    List<String> headers = const ['content-type', 'authorization'],
  }) {
    final corsHeaders = {
      'access-control-allow-origin': origin,
      'access-control-allow-methods': [...methods, 'OPTIONS'].join(', '),
      'access-control-allow-headers': headers.join(', '),
    };

    return (inner) => (request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok(null, headers: corsHeaders);
      }
      final response = await inner(request);

      return response.change(headers: corsHeaders);
    };
  }

  /// The full path of the OpenAPI document, or null when it's off.
  String? get _openApiUrl {
    final path = openApiPath;

    return docs && path != null ? joinPaths(prefix, path) : null;
  }

  /// The full path of the docs page, or null when it's off.
  String? get _docsUrl {
    final path = docsPath;

    return _openApiUrl != null && path != null ? joinPaths(prefix, path) : null;
  }

  void _addBuiltIns() {
    void addIfFree(String fullPath, Endpoint endpoint) {
      if (_router.find('GET', fullPath) != null) return;
      _router.add(fullPath, endpoint, builtIn: true);
    }

    if (healthPath case final path?) {
      addIfFree(
        joinPaths(prefix, path),
        Endpoint.get(run: (_) => {'status': 'ok'}),
      );
    }
    if ((version, versionPath) case (final version?, final path?)) {
      addIfFree(
        joinPaths(prefix, path),
        Endpoint.get(run: (_) => {'name': name, 'version': version}),
      );
    }
    if (_openApiUrl case final specUrl?) {
      addIfFree(specUrl, Endpoint.get(run: (_) => openApi));
      if (_docsUrl case final docsUrl?) {
        addIfFree(
          docsUrl,
          Endpoint.get(
            run: (_) => Response.ok(
              buildDocsPage(title: name, specUrl: specUrl),
              headers: {'content-type': 'text/html; charset=utf-8'},
            ),
          ),
        );
      }
    }
  }

  Handler _buildHandler() {
    var pipeline = const Pipeline();
    for (final m in middleware) {
      pipeline = pipeline.addMiddleware(m);
    }

    final site = website?.handler;
    if (site == null) return pipeline.addHandler(_handle);

    final prefix = joinPaths('', this.prefix);

    return pipeline.addHandler((request) {
      final path = joinPaths('', request.url.path);
      final isApi = path == prefix || path.startsWith('$prefix/');

      return isApi ? _handle(request) : site(request);
    });
  }

  Future<Response> _handle(Request request) async {
    try {
      final path = joinPaths('', request.url.path);
      final match = _router.match(request.method, path);
      final endpoint = match.target.endpoint;
      final input = await _readInput(request, match);
      final result = await endpoint.run(input);

      return _toResponse(result, endpoint.status);
    } on ApiError catch (error) {
      return _apiError(error);
    } catch (error, stack) {
      return _internalError(error, stack, request);
    }
  }

  Response _apiError(ApiError error) {
    final shape = errorBody;
    if (shape != null) {
      try {
        return _json(shape(error), error.status, error.headers);
      } catch (shapeError, stack) {
        _logFailure('errorBody failed for $error', shapeError, stack);
      }
    }

    return _json(error.toJson(), error.status, error.headers);
  }

  Future<Response> _internalError(
    Object error,
    StackTrace stack,
    Request request,
  ) async {
    final handle = onError;
    if (handle == null) {
      _logFailure(
        '${request.method} ${request.requestedUri} failed',
        error,
        stack,
      );
    } else {
      try {
        return await handle(error, stack, request);
      } catch (handlerError, handlerStack) {
        _logFailure('onError failed for $error', handlerError, handlerStack);
      }
    }

    return _json({'error': 'internal error'}, 500);
  }

  void _logFailure(String what, Object error, StackTrace stack) {
    fail('$what: $error');
    debug(stack);
  }

  Future<ApiInput> _readInput(Request request, RouteMatch match) async {
    final endpoint = match.target.endpoint;

    final params = {
      for (final p in match.target.params)
        p.name: p.parseText(match.rawParams[p.name]!),
    };

    final rawQuery = request.url.queryParameters;
    final query = {
      for (final q in endpoint.query)
        q.name: _fill(
          q,
          rawQuery.containsKey(q.name) ? q.parseText(rawQuery[q.name]!) : null,
        ),
    };

    Object? json;
    final body = <String, Object?>{};
    if (endpoint.body.isNotEmpty) {
      final text = await request.readAsString();
      if (text.trim().isNotEmpty) {
        try {
          json = jsonDecode(text);
        } on FormatException {
          throw const ApiError.badRequest('body must be valid JSON');
        }
      }
      json ??= <String, Object?>{};
      if (json is! Map) {
        throw const ApiError.badRequest('body must be a JSON object');
      }
      for (final field in endpoint.body) {
        final value = json[field.name];
        body[field.name] = _fill(
          field,
          value == null ? null : field.checkJson(value),
        );
      }
    }

    return ApiInput(
      request: request,
      params: Values(params),
      query: Values(query),
      body: Values(body),
      json: json,
    );
  }

  Object? _fill(Field field, Object? value) {
    if (value != null) return value;
    if (field.required) {
      throw ApiError.badRequest('${field.location} ${field.name} is required');
    }

    return field.defaultValue;
  }

  Response _toResponse(Object? result, int status) => switch (result) {
    final Response response => response,
    null => Response(204),
    _ => _json(result, status),
  };

  Response _json(
    Object? body,
    int status, [
    Map<String, String> headers = const {},
  ]) => Response(
    status,
    body: jsonEncode(body),
    headers: {...headers, 'content-type': 'application/json'},
  );
}
