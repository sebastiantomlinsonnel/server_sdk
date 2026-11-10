/// A mistake the caller made, sent back as JSON: `{"error": message}`.
///
/// Throw it from a `run` function to stop and answer with [status].
/// The framework throws it too, for bad params (400), unknown paths (404)
/// and wrong methods (405).
///
/// ```dart
/// Endpoint.get(
///   run: (input) {
///     final todo = todos[input.params.get<int>('id')];
///     if (todo == null) throw const ApiError.notFound('no such todo');
///
///     return todo;
///   },
/// );
/// ```
///
/// Answers `404` with `{"error": "no such todo"}`.
class ApiError implements Exception {
  /// The HTTP status code to answer with.
  final int status;

  /// The message shown to the caller under `error`.
  final String message;

  /// Extra JSON sent under `details`, when given.
  final Object? details;

  /// Extra response headers, like `allow` for a 405.
  final Map<String, String> headers;

  /// Creates an error answered with [status] and [message].
  const ApiError(
    this.status,
    this.message, {
    this.details,
    this.headers = const {},
  });

  /// A 400: the request was malformed or failed validation.
  const ApiError.badRequest(String message, {Object? details})
    : this(400, message, details: details);

  /// A 401: the caller isn't logged in.
  const ApiError.unauthorized([String message = 'unauthorized'])
    : this(401, message);

  /// A 403: the caller may not do this.
  const ApiError.forbidden([String message = 'forbidden']) : this(403, message);

  /// A 404: the thing asked for doesn't exist.
  const ApiError.notFound([String message = 'not found']) : this(404, message);

  /// A 409: the request clashes with the current state.
  const ApiError.conflict(String message) : this(409, message);

  /// The JSON body sent to the caller.
  Map<String, Object?> toJson() => {
    'error': message,
    if (details != null) 'details': details,
  };

  @override
  String toString() => 'ApiError($status): $message';
}
