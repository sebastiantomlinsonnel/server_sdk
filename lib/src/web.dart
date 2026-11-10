import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

import 'endpoint.dart';
import 'errors.dart';
import 'flutter_project.dart';
import 'input.dart';
import 'openapi.dart';
import 'params.dart';
import 'route.dart';
import 'router.dart';
import 'serve.dart';
import 'website.dart';

/// An HTTP API described as a tree of [Route]s.
///
/// Handles the plumbing for you:
/// * Path, query and body values are checked against their declarations;
///   a mistake answers 400 with `{"error": "..."}`.
/// * Unknown paths answer 404, known paths with the wrong method 405.
/// * `run` results are sent as JSON; `null` answers 204.
/// * A thrown [ApiError] answers with its status; any other exception is
///   logged and answers 500.
/// * `GET <prefix>/health` is always there, and `GET <prefix>/version` when
///   [version] is set. Declare your own to replace them.
/// * `GET <prefix>/openapi.json` and `GET <prefix>/docs` describe every
///   route, unless [docs] is false.
/// * With a [website], every path outside [prefix] is served from it, so the
///   site and the API share one origin.
class WEB {
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

  final Router _router = Router();
  Handler? _handler;

  /// Creates the API. Throws an [ArgumentError] when two endpoints clash, a
  /// [PathParam] isn't in its path, or a [website] is given without a
  /// [prefix].
  WEB({
    required this.name,
    this.version,
    this.help,
    this.prefix = '',
    this.middleware = const [],
    this.routes = const [],
    this.docs = true,
    this.website,
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
  Handler get handler => _handler ??= _buildHandler();

  /// Gets the [website] ready (building it when needed), then starts
  /// listening and prints where.
  ///
  /// [port] defaults to the `PORT` environment variable, then 8080.
  Future<HttpServer> serve({Object? host, int? port}) async {
    await website?.prepare();
    final prefix = joinPaths('', this.prefix);

    return startServer(
      handler, // Built before binding, so a missing website fails early.
      host: host,
      port: port,
      banner: (base) => [
        if (website != null) 'Website at $base/',
        'API $name${version == null ? '' : ' $version'} '
            'at $base${prefix == '/' ? '' : prefix}',
        if (docs) 'Docs at $base${joinPaths(prefix, 'docs')}',
      ],
    );
  }

  /// Middleware that lets browsers on other origins call the API, and answers
  /// `OPTIONS` preflight requests.
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

  void _addBuiltIns() {
    void addIfFree(String path, Endpoint endpoint) {
      final fullPath = joinPaths(prefix, path);
      if (_router.find('GET', fullPath) != null) return;
      _router.add(fullPath, endpoint, builtIn: true);
    }

    addIfFree('health', Endpoint.get(run: (_) => {'status': 'ok'}));
    final version = this.version;
    if (version != null) {
      addIfFree(
        'version',
        Endpoint.get(run: (_) => {'name': name, 'version': version}),
      );
    }
    if (docs) {
      addIfFree('openapi.json', Endpoint.get(run: (_) => openApi));
      addIfFree(
        'docs',
        Endpoint.get(
          run: (_) => Response.ok(
            buildDocsPage(
              title: name,
              specUrl: joinPaths(prefix, 'openapi.json'),
            ),
            headers: {'content-type': 'text/html; charset=utf-8'},
          ),
        ),
      );
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
      return _json(error.toJson(), error.status, error.headers);
    } catch (error, stack) {
      stderr
        ..writeln('${request.method} ${request.requestedUri} failed: $error')
        ..writeln(stack);

      return _json({'error': 'internal error'}, 500);
    }
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
