import 'endpoint.dart';
import 'errors.dart';
import 'params.dart';
import 'route.dart';

/// One endpoint with its full path, ready to match requests.
class CompiledEndpoint {
  /// The full path with `<name>` segments, like `/api/todos/<id>`.
  final String path;

  /// The endpoint itself.
  final Endpoint endpoint;

  /// The path params, in the order they appear in [path].
  final List<PathParam> params;

  /// The doc group, from the nearest route with `help`.
  final String? tag;

  /// Whether the framework added it (health, version, docs).
  final bool builtIn;

  final RegExp _pattern;

  CompiledEndpoint._(
    this.path,
    this.endpoint,
    this.params,
    this.tag,
    this.builtIn,
    this._pattern,
  );

  /// The path written OpenAPI style, like `/api/todos/{id}`.
  String get openApiPath =>
      path.replaceAllMapped(_paramSegment, (m) => '{${m[1]}}');
}

/// The match for one request.
class RouteMatch {
  /// The endpoint that answers.
  final CompiledEndpoint target;

  /// The raw text of each path param.
  final Map<String, String> rawParams;

  /// Creates a match for [target] with the raw path params in [rawParams].
  const RouteMatch(this.target, this.rawParams);
}

final _paramSegment = RegExp(r'<([A-Za-z_][A-Za-z0-9_]*)>');

/// Finds the endpoint for a method and path.
class Router {
  /// Every endpoint, in declaration order.
  final List<CompiledEndpoint> endpoints = [];

  /// Adds [route] and its children below [prefix].
  void addRoute(
    Route route, {
    String prefix = '',
    List<PathParam> inherited = const [],
    String? tag,
    bool builtIn = false,
  }) {
    final path = joinPaths(prefix, route.path);
    final params = [...inherited, ...route.params];
    final routeTag = route.help ?? tag;

    for (final endpoint in route.endpoints) {
      add(path, endpoint, params: params, tag: routeTag, builtIn: builtIn);
    }
    for (final child in route.routes) {
      addRoute(
        child,
        prefix: path,
        inherited: params,
        tag: routeTag,
        builtIn: builtIn,
      );
    }
  }

  /// Adds one endpoint at the full [path].
  ///
  /// Throws an [ArgumentError] for a clash or a param missing from the path.
  void add(
    String path,
    Endpoint endpoint, {
    List<PathParam> params = const [],
    String? tag,
    bool builtIn = false,
  }) {
    final method = endpoint.method.toUpperCase();
    final names = [for (final m in _paramSegment.allMatches(path)) m[1]!];
    final byName = {for (final p in params) p.name: p};

    final unknown = byName.keys.toSet().difference(names.toSet());
    if (unknown.isNotEmpty) {
      throw ArgumentError(
        'Path $path declares params ${unknown.join(', ')} that are not in it',
      );
    }
    if (names.toSet().length != names.length) {
      throw ArgumentError('Path $path uses the same param twice');
    }
    if (find(method, path) case final existing?) {
      throw ArgumentError('$method ${existing.path} is declared twice');
    }

    final pattern = path
        .split('/')
        .map(
          (segment) => _paramSegment.hasMatch(segment)
              ? segment.splitMapJoin(
                  _paramSegment,
                  onMatch: (_) => '([^/]+)',
                  onNonMatch: RegExp.escape,
                )
              : RegExp.escape(segment),
        )
        .join('/');

    endpoints.add(
      CompiledEndpoint._(
        path,
        endpoint,
        [for (final name in names) byName[name] ?? PathParam.string(name)],
        tag,
        builtIn,
        RegExp('^$pattern\$'),
      ),
    );
  }

  /// The endpoint declared for [method] at exactly [path], if any.
  CompiledEndpoint? find(String method, String path) {
    final normalized = path.replaceAll(_paramSegment, '<>');
    for (final e in endpoints) {
      if (e.endpoint.method.toUpperCase() == method &&
          e.path.replaceAll(_paramSegment, '<>') == normalized) {
        return e;
      }
    }

    return null;
  }

  /// Finds the endpoint for a request.
  ///
  /// Throws a 404 [ApiError] when no path matches, and a 405 (with an
  /// `allow` header) when the path exists but not for [method].
  RouteMatch match(String method, String path) {
    final wanted = method.toUpperCase();
    final allowed = <String>{};

    for (final e in endpoints) {
      final m = e._pattern.firstMatch(path);
      if (m == null) continue;

      final endpointMethod = e.endpoint.method.toUpperCase();
      if (endpointMethod == wanted ||
          (wanted == 'HEAD' && endpointMethod == 'GET')) {
        return RouteMatch(e, {
          for (var i = 0; i < e.params.length; i++)
            e.params[i].name: Uri.decodeComponent(m[i + 1]!),
        });
      }
      allowed.add(endpointMethod);
    }

    if (allowed.isEmpty) throw const ApiError.notFound();

    throw ApiError(
      405,
      'method $wanted not allowed',
      headers: {'allow': allowed.join(', ')},
    );
  }
}

/// Joins path parts with single slashes, with a leading slash and no
/// trailing one (except for the root, `/`).
String joinPaths(String a, String b) {
  final parts = '$a/$b'.split('/').where((part) => part.isNotEmpty);
  final joined = '/${parts.join('/')}';

  return joined;
}
