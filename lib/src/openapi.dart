import 'dart:convert';

import 'router.dart';

/// Describes [endpoints] as an OpenAPI 3.1 document.
Map<String, Object?> buildOpenApi({
  required String title,
  required String? version,
  required String? description,
  required Iterable<CompiledEndpoint> endpoints,
}) {
  final paths = <String, Map<String, Object?>>{};
  final tags = <String>{};

  for (final e in endpoints) {
    final endpoint = e.endpoint;
    final endpointTags = endpoint.tags ?? [?e.tag];
    tags.addAll(endpointTags);

    final parameters = [
      for (final p in e.params)
        {
          'name': p.name,
          'in': 'path',
          'required': true,
          'description': ?p.help,
          'schema': p.schema,
        },
      for (final q in endpoint.query)
        {
          'name': q.name,
          'in': 'query',
          'required': q.required,
          'description': ?q.help,
          'schema': q.schema,
        },
    ];

    final body = endpoint.body;
    final required = [
      for (final f in body)
        if (f.required) f.name,
    ];

    paths.putIfAbsent(e.openApiPath, () => {})[endpoint.method
        .toLowerCase()] = {
      'summary': ?endpoint.help,
      if (endpointTags.isNotEmpty) 'tags': endpointTags,
      if (parameters.isNotEmpty) 'parameters': parameters,
      if (body.isNotEmpty)
        'requestBody': {
          'required': required.isNotEmpty,
          'content': {
            'application/json': {
              'schema': {
                'type': 'object',
                'properties': {
                  for (final f in body)
                    f.name: {...f.schema, 'description': ?f.help},
                },
                if (required.isNotEmpty) 'required': required,
              },
            },
          },
        },
      'responses': {
        '${endpoint.status}': {'description': 'Success'},
        if (parameters.isNotEmpty || body.isNotEmpty)
          '400': {'description': 'Invalid input'},
      },
    };
  }

  return {
    'openapi': '3.1.0',
    'info': {
      'title': title,
      'version': version ?? '0.0.0',
      'description': ?description,
    },
    if (tags.isNotEmpty)
      'tags': [
        for (final tag in tags) {'name': tag},
      ],
    'paths': paths,
  };
}

/// A page that shows the OpenAPI document at [specUrl] with Swagger UI.
String buildDocsPage({required String title, required String specUrl}) {
  final safeTitle = const HtmlEscape().convert(title);

  return '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$safeTitle docs</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5.17.14/swagger-ui.css">
</head>
<body>
  <div id="docs"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5.17.14/swagger-ui-bundle.js"></script>
  <script>
    SwaggerUIBundle({ url: ${_jsString(specUrl)}, dom_id: '#docs' });
  </script>
</body>
</html>
''';
}

String _jsString(String value) =>
    "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll('<', r'\x3c')}'";
