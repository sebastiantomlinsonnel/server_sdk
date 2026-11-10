import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

/// Something a `WEB` serves next to its API, for every path outside the
/// API's prefix.
abstract class Website {
  /// Creates a website.
  const Website();

  /// Gets the website ready before the server starts, like building it.
  /// Does nothing by default.
  Future<void> prepare() async {}

  /// The shelf handler that answers website requests.
  Handler get handler;
}

/// A folder of static files.
class StaticWebsite extends Website {
  /// The folder the files are served from.
  final String directory;

  /// The file served for `/` and, with [spaFallback], for unknown pages.
  final String indexFile;

  /// Whether paths without a file extension that don't exist get
  /// [indexFile], so apps with their own routing work on reload.
  final bool spaFallback;

  /// The `cache-control` header for every file, when given.
  final String? cacheControl;

  /// Extra headers added to every response.
  final Map<String, String> headers;

  /// Creates a website from [directory].
  StaticWebsite(
    this.directory, {
    this.indexFile = 'index.html',
    this.spaFallback = false,
    this.cacheControl,
    this.headers = const {},
  });

  /// Whether [directory] exists.
  bool get exists => Directory(directory).existsSync();

  /// Throws a [StateError] when [directory] doesn't exist.
  @override
  late final Handler handler = _build();

  /// The message used when [directory] is missing.
  String get missingMessage => 'Website folder $directory does not exist';

  Handler _build() {
    if (!exists) throw StateError(missingMessage);

    final files = createStaticHandler(directory, defaultDocument: indexFile);
    final index = File('$directory${Platform.pathSeparator}$indexFile');
    final extra = {...headers, 'cache-control': ?cacheControl};

    return (request) async {
      if (request.method != 'GET' && request.method != 'HEAD') {
        return Response(405, headers: {'allow': 'GET, HEAD'});
      }

      var response = await files(request);
      if (response.statusCode == 404 &&
          spaFallback &&
          !_lastSegment(request).contains('.') &&
          index.existsSync()) {
        response = Response.ok(
          request.method == 'HEAD' ? null : index.openRead(),
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }

      return response.change(headers: extra);
    };
  }

  static String _lastSegment(Request request) {
    final segments = request.url.pathSegments;

    return segments.isEmpty ? '' : segments.last;
  }
}

/// The output of `flutter build web`, with the right defaults for it:
/// * unknown pages get `index.html`, so path URLs work on reload;
/// * files are revalidated on each load, since Flutter's file names don't
///   change between builds;
/// * with [crossOriginIsolated], the headers multi-threaded `--wasm` builds
///   need are sent.
class FlutterWebsite extends StaticWebsite {
  /// Whether `cross-origin-opener-policy` and
  /// `cross-origin-embedder-policy` headers are sent.
  final bool crossOriginIsolated;

  /// Serves the Flutter build in [directory], usually `app/build/web`.
  FlutterWebsite(super.directory, {this.crossOriginIsolated = false})
    : super(
        spaFallback: true,
        cacheControl: 'no-cache',
        headers: crossOriginIsolated
            ? const {
                'cross-origin-opener-policy': 'same-origin',
                'cross-origin-embedder-policy': 'require-corp',
              }
            : const {},
      );

  @override
  String get missingMessage =>
      'Flutter build $directory does not exist. '
      'Run `flutter build web` in your Flutter app first.';
}
