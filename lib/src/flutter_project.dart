import 'dart:io';

import 'package:cmdline/logging.dart';
import 'package:shelf/shelf.dart';

import 'website.dart';

/// When a [FlutterProject] runs `flutter build web` before the server starts.
enum FlutterBuild {
  /// Never build; serve whatever is in `build/web`. Use this on servers
  /// without the Flutter SDK, with the build made in CI or Docker.
  never,

  /// Build only when `build/web` doesn't exist yet.
  ifMissing,

  /// Build when a source file is newer than the last build, or the build
  /// settings changed. Handy while working locally.
  ifChanged,

  /// Build every time the server starts.
  always,
}

/// Runs [executable] with [arguments] in [workingDirectory] and returns its
/// exit code. Swap it out in tests to skip the real Flutter build.
typedef BuildRunner = Future<int> Function(
  String executable,
  List<String> arguments,
  String workingDirectory,
);

/// Thrown when `flutter build web` fails, so the server doesn't start with
/// an old or missing build.
class FlutterBuildException implements Exception {
  /// The exit code of `flutter build web`.
  final int exitCode;

  /// The project folder that failed to build.
  final String project;

  /// Creates the exception.
  const FlutterBuildException(this.project, this.exitCode);

  @override
  String toString() =>
      'flutter build web failed in $project with exit code $exitCode';
}

/// A Flutter app, served from its `build/web` folder and built when [build]
/// says so.
///
/// Serving uses the [FlutterWebsite] defaults: unknown pages get
/// `index.html`, files are revalidated on each load, and
/// [crossOriginIsolated] adds the headers multi-threaded `--wasm` builds need.
///
/// ```dart
/// final server = WEB(
///   name: 'my app',
///   prefix: '/api', // required when there's a website
///   routes: [...],
///   website: FlutterProject(
///     '../app',
///     build: FlutterBuild.ifChanged,
///     dartDefines: {'API_URL': '/api'},
///   ),
/// );
///
/// await server.serve(); // builds ../app if needed, then serves both
/// ```
class FlutterProject extends Website {
  /// The Flutter project folder, the one with `pubspec.yaml`. A relative path
  /// is read from the current working folder.
  final String directory;

  /// When to run `flutter build web`.
  final FlutterBuild build;

  /// Whether to build with `--wasm`.
  final bool wasm;

  /// Values passed as `--dart-define=key=value`.
  final Map<String, String> dartDefines;

  /// Extra arguments for `flutter build web`, like `--release` or
  /// `--base-href=/app/`.
  final List<String> buildArgs;

  /// Extra files or folders that count as sources for [FlutterBuild.ifChanged],
  /// like a shared package. Relative paths are read from [directory].
  final List<String> watch;

  /// Whether `cross-origin-opener-policy` and `cross-origin-embedder-policy`
  /// headers are sent.
  final bool crossOriginIsolated;

  /// The Flutter command. Defaults to `flutter` from the PATH.
  final String flutter;

  final BuildRunner _runner;

  /// Points at the Flutter project in [directory].
  FlutterProject(
    this.directory, {
    this.build = FlutterBuild.ifMissing,
    this.wasm = false,
    this.dartDefines = const {},
    this.buildArgs = const [],
    this.watch = const [],
    this.crossOriginIsolated = false,
    this.flutter = 'flutter',
    BuildRunner? runner,
  }) : _runner = runner ?? _runProcess;

  /// The folder `flutter build web` writes to and the server serves.
  String get buildDirectory => _join(directory, 'build/web');

  /// The arguments passed to `flutter`.
  List<String> get arguments => [
    'build',
    'web',
    if (wasm) '--wasm',
    for (final MapEntry(:key, :value) in dartDefines.entries)
      '--dart-define=$key=$value',
    ...buildArgs,
  ];

  late final FlutterWebsite _site = FlutterWebsite(
    buildDirectory,
    crossOriginIsolated: crossOriginIsolated,
  );

  /// Builds the app when [build] says so. Throws a [FlutterBuildException]
  /// when the build fails, and a [StateError] when [directory] has no
  /// `pubspec.yaml`.
  @override
  Future<void> prepare() async {
    if (!File(_join(directory, 'pubspec.yaml')).existsSync()) {
      throw StateError('$directory is not a Flutter project (no pubspec.yaml)');
    }
    if (!needsBuild) return;

    trace('Building $directory: $flutter ${arguments.join(' ')}');
    final exitCode = await _runner(flutter, arguments, directory);
    if (exitCode != 0) throw FlutterBuildException(directory, exitCode);

    File(_stampPath).writeAsStringSync(arguments.join('\n'));
  }

  /// Whether [prepare] would run `flutter build web` now.
  bool get needsBuild {
    final built = Directory(buildDirectory).existsSync();

    return switch (build) {
      FlutterBuild.never => false,
      FlutterBuild.ifMissing => !built,
      FlutterBuild.always => true,
      FlutterBuild.ifChanged => !built || _changed(),
    };
  }

  /// Throws a [StateError] when there's no build yet.
  @override
  Handler get handler => _site.handler;

  /// Records the settings of the last build; its time is the build time.
  String get _stampPath => _join(directory, 'build/.server_sdk_build');

  bool _changed() {
    final stamp = File(_stampPath);
    if (!stamp.existsSync()) return true;
    if (stamp.readAsStringSync() != arguments.join('\n')) return true;

    final builtAt = stamp.lastModifiedSync();
    final sources = [
      'lib',
      'web',
      'assets',
      'pubspec.yaml',
      ...watch,
    ].map((path) => _join(directory, path));

    return sources.any((path) => _newerThan(path, builtAt));
  }

  static bool _newerThan(String path, DateTime time) {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.file) {
      return File(path).lastModifiedSync().isAfter(time);
    }
    if (type != FileSystemEntityType.directory) return false;

    return Directory(path)
        .listSync(recursive: true)
        .whereType<File>()
        .any((file) => file.lastModifiedSync().isAfter(time));
  }

  static String _join(String base, String path) {
    if (File(path).isAbsolute) return path;
    final separator = Platform.pathSeparator;
    final trimmed = base.endsWith('/') || base.endsWith(separator)
        ? base.substring(0, base.length - 1)
        : base;

    return '$trimmed$separator${path.replaceAll('/', separator)}';
  }

  static Future<int> _runProcess(
    String executable,
    List<String> arguments,
    String workingDirectory,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: Platform.isWindows, // flutter is a .bat file there.
      mode: ProcessStartMode.inheritStdio,
    );

    return process.exitCode;
  }
}
