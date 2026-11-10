import 'errors.dart';

/// The JSON type a [Field] holds.
enum ParamType {
  string('string'),
  int('integer'),
  double('number'),
  bool('boolean'),
  map('object'),
  list('array');

  /// The name OpenAPI uses for this type.
  final String openApiName;

  const ParamType(this.openApiName);
}

/// Something the caller sends: a path param, query param or body field.
abstract class Field {
  /// The name used in the path, query string or JSON body.
  final String name;

  /// The type the value is checked against and converted to.
  final ParamType type;

  /// A one-line description shown in the docs.
  final String? help;

  /// Whether the request fails with 400 when it is missing.
  final bool required;

  /// The value used when the caller leaves it out.
  final Object? defaultValue;

  /// When given, the value must be one of these.
  final List<Object>? allowed;

  const Field(
    this.name,
    this.type, {
    this.help,
    this.required = false,
    this.defaultValue,
    this.allowed,
  });

  /// Where the value comes from, for messages and OpenAPI (`path`, `query`,
  /// `body`).
  String get location;

  /// Turns the text from a path or query string into [type].
  Object? parseText(String text) {
    final Object? value = switch (type) {
      ParamType.string => text,
      ParamType.int => int.tryParse(text),
      ParamType.double => double.tryParse(text),
      ParamType.bool => switch (text.toLowerCase()) {
        '' || 'true' || '1' || 'yes' => true,
        'false' || '0' || 'no' => false,
        _ => null,
      },
      ParamType.map || ParamType.list => null,
    };
    if (value == null) throw _wrongType();

    return _checkAllowed(value);
  }

  /// Checks a decoded JSON value against [type].
  Object? checkJson(Object? value) {
    final Object? checked = switch (type) {
      ParamType.string => value is String ? value : null,
      ParamType.int => value is int ? value : null,
      ParamType.double => value is num ? value.toDouble() : null,
      ParamType.bool => value is bool ? value : null,
      ParamType.map => value is Map ? value.cast<String, Object?>() : null,
      ParamType.list => value is List ? value : null,
    };
    if (checked == null) throw _wrongType();

    return _checkAllowed(checked);
  }

  /// The JSON schema of this field, for OpenAPI.
  Map<String, Object?> get schema => {
    'type': type.openApiName,
    if (allowed != null) 'enum': allowed,
    if (defaultValue != null) 'default': defaultValue,
  };

  Object _checkAllowed(Object value) {
    final allowed = this.allowed;
    if (allowed != null && !allowed.contains(value)) {
      throw ApiError.badRequest(
        '$location $name must be one of ${allowed.join(', ')}',
      );
    }

    return value;
  }

  ApiError _wrongType() {
    final article = type == ParamType.int ? 'an' : 'a';

    return ApiError.badRequest(
      '$location $name must be $article ${type.openApiName}',
    );
  }
}

/// A `<name>` segment in a [Route] path, like `/todos/<id>`.
///
/// Path params are always required. A `<name>` in a path with no matching
/// [PathParam] is treated as a string.
class PathParam extends Field {
  /// A param kept as text.
  const PathParam.string(String name, {String? help, List<String>? allowed})
    : super(
        name,
        ParamType.string,
        help: help,
        required: true,
        allowed: allowed,
      );

  /// A whole-number param. Anything else answers 400.
  const PathParam.int(String name, {String? help})
    : super(name, ParamType.int, help: help, required: true);

  /// A decimal-number param. Anything else answers 400.
  const PathParam.double(String name, {String? help})
    : super(name, ParamType.double, help: help, required: true);

  @override
  String get location => 'path';
}

/// A `?name=value` part of the URL.
class QueryParam extends Field {
  /// A param kept as text.
  const QueryParam.string(
    String name, {
    String? help,
    bool required = false,
    String? defaultValue,
    List<String>? allowed,
  }) : super(
         name,
         ParamType.string,
         help: help,
         required: required,
         defaultValue: defaultValue,
         allowed: allowed,
       );

  /// A whole-number param.
  const QueryParam.int(
    String name, {
    String? help,
    bool required = false,
    int? defaultValue,
  }) : super(
         name,
         ParamType.int,
         help: help,
         required: required,
         defaultValue: defaultValue,
       );

  /// A decimal-number param.
  const QueryParam.double(
    String name, {
    String? help,
    bool required = false,
    double? defaultValue,
  }) : super(
         name,
         ParamType.double,
         help: help,
         required: required,
         defaultValue: defaultValue,
       );

  /// A yes/no param. `?name`, `?name=true` and `?name=1` all mean true.
  const QueryParam.bool(
    String name, {
    String? help,
    bool required = false,
    bool? defaultValue,
  }) : super(
         name,
         ParamType.bool,
         help: help,
         required: required,
         defaultValue: defaultValue,
       );

  @override
  String get location => 'query';
}

/// A field of the JSON object sent as the request body.
class BodyField extends Field {
  /// A JSON string.
  const BodyField.string(
    String name, {
    String? help,
    bool required = false,
    String? defaultValue,
    List<String>? allowed,
  }) : super(
         name,
         ParamType.string,
         help: help,
         required: required,
         defaultValue: defaultValue,
         allowed: allowed,
       );

  /// A JSON whole number.
  const BodyField.int(
    String name, {
    String? help,
    bool required = false,
    int? defaultValue,
  }) : super(
         name,
         ParamType.int,
         help: help,
         required: required,
         defaultValue: defaultValue,
       );

  /// A JSON number, read as a double.
  const BodyField.double(
    String name, {
    String? help,
    bool required = false,
    double? defaultValue,
  }) : super(
         name,
         ParamType.double,
         help: help,
         required: required,
         defaultValue: defaultValue,
       );

  /// A JSON `true` or `false`.
  const BodyField.bool(
    String name, {
    String? help,
    bool required = false,
    bool? defaultValue,
  }) : super(
         name,
         ParamType.bool,
         help: help,
         required: required,
         defaultValue: defaultValue,
       );

  /// A JSON object.
  const BodyField.map(String name, {String? help, bool required = false})
    : super(name, ParamType.map, help: help, required: required);

  /// A JSON array.
  const BodyField.list(String name, {String? help, bool required = false})
    : super(name, ParamType.list, help: help, required: required);

  @override
  String get location => 'body field';
}
