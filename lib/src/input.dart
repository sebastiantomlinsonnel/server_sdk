import 'package:shelf/shelf.dart';

import 'errors.dart';

/// Checked values from one part of the request (path, query or body).
class Values {
  final Map<String, Object?> _values;

  /// Wraps already-checked values.
  const Values(this._values);

  /// Whether the caller sent [name] (or it has a default).
  bool has(String name) => _values[name] != null;

  /// The value of [name], or null when it wasn't sent.
  Object? operator [](String name) => _values[name];

  /// The value of [name] as [T].
  ///
  /// Throws a 400 [ApiError] when it is missing, so it is safe for required
  /// fields. Use [maybe] for optional ones.
  T get<T>(String name) {
    final value = _values[name];
    if (value == null) throw ApiError.badRequest('$name is required');

    return value as T;
  }

  /// The value of [name] as [T], or null when it wasn't sent.
  T? maybe<T>(String name) => _values[name] as T?;

  /// All values, by name.
  Map<String, Object?> toMap() => Map.unmodifiable(_values);
}

/// Everything a `run` function gets about the request.
class ApiInput {
  /// The raw shelf request. Its body is already read when the endpoint
  /// declares body fields; use [json] then.
  final Request request;

  /// Path params like `<id>`, converted to their declared types.
  final Values params;

  /// Query params, converted and with defaults filled in.
  final Values query;

  /// Declared body fields, checked and with defaults filled in.
  final Values body;

  /// The whole decoded JSON body, or null when the endpoint declares no body
  /// fields.
  final Object? json;

  /// Creates the input for one request.
  const ApiInput({
    required this.request,
    this.params = const Values({}),
    this.query = const Values({}),
    this.body = const Values({}),
    this.json,
  });
}
