import 'dart:async';

import 'input.dart';
import 'params.dart';

/// What an endpoint does. It may return:
/// * a shelf `Response`, sent as it is;
/// * `null`, answered with 204 No Content;
/// * anything else, sent as JSON (objects with `toJson()` work) with the
///   endpoint's [Endpoint.status].
typedef RunFunction = FutureOr<Object?> Function(ApiInput input);

/// One HTTP method on a [Route], like `GET /todos`.
class Endpoint {
  /// The HTTP method, in capitals.
  final String method;

  /// A one-line description shown in the docs.
  final String? help;

  /// The status sent when [run] returns a value. Defaults to 200.
  final int status;

  /// The `?name=value` params this endpoint reads.
  final List<QueryParam> query;

  /// The JSON body fields this endpoint reads. When not empty, the body must
  /// be a JSON object.
  final List<BodyField> body;

  /// Groups shown together in the docs. Defaults to the route's tag.
  final List<String>? tags;

  /// The function that answers the request.
  final RunFunction run;

  /// Creates an endpoint for any [method].
  const Endpoint(
    this.method, {
    required this.run,
    this.help,
    this.status = 200,
    this.query = const [],
    this.body = const [],
    this.tags,
  });

  /// A `GET` endpoint.
  const Endpoint.get({
    required RunFunction run,
    String? help,
    int status = 200,
    List<QueryParam> query = const [],
    List<String>? tags,
  }) : this(
         'GET',
         run: run,
         help: help,
         status: status,
         query: query,
         tags: tags,
       );

  /// A `POST` endpoint.
  const Endpoint.post({
    required RunFunction run,
    String? help,
    int status = 200,
    List<QueryParam> query = const [],
    List<BodyField> body = const [],
    List<String>? tags,
  }) : this(
         'POST',
         run: run,
         help: help,
         status: status,
         query: query,
         body: body,
         tags: tags,
       );

  /// A `PUT` endpoint.
  const Endpoint.put({
    required RunFunction run,
    String? help,
    int status = 200,
    List<QueryParam> query = const [],
    List<BodyField> body = const [],
    List<String>? tags,
  }) : this(
         'PUT',
         run: run,
         help: help,
         status: status,
         query: query,
         body: body,
         tags: tags,
       );

  /// A `PATCH` endpoint.
  const Endpoint.patch({
    required RunFunction run,
    String? help,
    int status = 200,
    List<QueryParam> query = const [],
    List<BodyField> body = const [],
    List<String>? tags,
  }) : this(
         'PATCH',
         run: run,
         help: help,
         status: status,
         query: query,
         body: body,
         tags: tags,
       );

  /// A `DELETE` endpoint.
  const Endpoint.delete({
    required RunFunction run,
    String? help,
    int status = 200,
    List<QueryParam> query = const [],
    List<String>? tags,
  }) : this(
         'DELETE',
         run: run,
         help: help,
         status: status,
         query: query,
         tags: tags,
       );
}
