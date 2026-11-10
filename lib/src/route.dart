import 'endpoint.dart';
import 'params.dart';

/// A path in the API, like `/todos` or `/todos/<id>`.
///
/// Routes nest like commands in a CLI: a child's path is added to its
/// parent's, and it inherits the parent's [params].
class Route {
  /// The path, relative to the parent. `<name>` segments are path params.
  final String path;

  /// A one-line description, shown as the group name in the docs.
  final String? help;

  /// Types for the `<name>` segments in [path].
  final List<PathParam> params;

  /// The methods this path answers.
  final List<Endpoint> endpoints;

  /// Paths below this one.
  final List<Route> routes;

  /// Creates a route.
  const Route(
    this.path, {
    this.help,
    this.params = const [],
    this.endpoints = const [],
    this.routes = const [],
  });
}
