// A todo app: a website and the JSON API it calls, served together.
//
// Run it with `dart run example/example.dart`, then open:
//
// * http://localhost:8080/          the website (from example/web)
// * http://localhost:8080/api/docs  the generated API docs
//
// Or call the API directly:
//
//   curl localhost:8080/api/todos
//   curl "localhost:8080/api/todos?done=false&limit=5"
//   curl -X POST localhost:8080/api/todos -d '{"title": "Write docs"}'
//   curl localhost:8080/api/todos/1
//   curl -X PATCH localhost:8080/api/todos/1 -d '{"done": true}'
//   curl -X DELETE localhost:8080/api/todos/1
import 'package:server_sdk/server_sdk.dart';

/// One item on the list. Objects with `toJson()` are sent as JSON as-is.
class Todo {
  Todo(this.id, this.title, {this.priority = 'normal'});

  final int id;
  String title;
  String priority;
  bool done = false;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'priority': priority,
    'done': done,
  };
}

final todos = <int, Todo>{1: Todo(1, 'Try server_sdk')};
var nextId = 2;

/// Finds the todo for the `<id>` in the path, or answers 404.
Todo findTodo(ApiInput input) {
  final id = input.params.get<int>('id');

  return todos[id] ?? (throw ApiError.notFound('todo $id not found'));
}

Future<void> main() async {
  final WEB api = WEB(
    name: 'todos',
    version: '1.0.0',
    help: 'A small todo list API.',
    website: FlutterWebsite('example/website'),
    prefix: '/api',
    middleware: [logRequests()],
    routes: [
      Route(
        '/todos',
        help: 'Todos',
        endpoints: [
          Endpoint.get(
            help: 'List todos',
            query: [
              const QueryParam.bool('done', help: 'Only done or not done'),
              const QueryParam.int('limit', defaultValue: 50),
            ],
            run: (input) {
              final done = input.query.maybe<bool>('done');
              final limit = input.query.get<int>('limit');
              if (limit < 1)
                throw const ApiError.badRequest('limit must be 1+');

              return todos.values
                  .where((todo) => done == null || todo.done == done)
                  .take(limit)
                  .toList();
            },
          ),
          Endpoint.post(
            help: 'Add a todo',
            status: 201,
            body: [
              const BodyField.string('title', required: true),
              const BodyField.string(
                'priority',
                defaultValue: 'normal',
                allowed: ['low', 'normal', 'high'],
              ),
            ],
            run: (input) {
              final title = input.body.get<String>('title').trim();
              if (title.isEmpty) {
                throw const ApiError.badRequest('title must not be empty');
              }
              final todo = Todo(
                nextId++,
                title,
                priority: input.body.get<String>('priority'),
              );

              return todos[todo.id] = todo;
            },
          ),
        ],
        routes: [
          Route(
            '/<id>',
            params: [const PathParam.int('id', help: 'The todo id')],
            endpoints: [
              Endpoint.get(help: 'Get one todo', run: findTodo),
              Endpoint.patch(
                help: 'Change a todo',
                body: [
                  const BodyField.string('title'),
                  const BodyField.bool('done'),
                ],
                run: (input) {
                  final todo = findTodo(input);
                  if (input.body.maybe<String>('title') case final title?) {
                    todo.title = title;
                  }
                  if (input.body.maybe<bool>('done') case final done?) {
                    todo.done = done;
                  }

                  return todo;
                },
              ),
              Endpoint.delete(
                help: 'Delete a todo',
                // Returning null answers 204 No Content.
                run: (input) {
                  todos.remove(findTodo(input).id);

                  return null;
                },
              ),
            ],
          ),
        ],
      ),
      Route(
        '/stats',
        help: 'Stats',
        endpoints: [
          Endpoint.get(
            help: 'Count todos',
            // Return a shelf Response to control the reply fully.
            run: (_) => Response.ok(
              '${todos.length} todos\n',
              headers: {'content-type': 'text/plain'},
            ),
          ),
        ],
      ),
    ],
  );

  // Also serves GET /api/health, /api/version, /api/openapi.json and
  // /api/docs.
  await api.serve();
}
