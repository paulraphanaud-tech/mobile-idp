import 'dart:io';

import 'package:args/args.dart';

import 'diagnostics.dart';
import 'events/codegen.dart';
import 'events/parser.dart';
import 'flags/codegen.dart';
import 'flags/model.dart';
import 'flags/parser.dart';
import 'flags/render.dart';
import 'tokens/codegen.dart';
import 'tokens/parser.dart';

const _usage = '''
idp_codegen — registry validation and code generation for the mobile IDP.

  flags validate   --registry flags/flags.yaml [--strict-expiry]
  flags codegen    --registry flags/flags.yaml --out lib/generated/flags.g.dart [--check]
  flags render     --registry flags/flags.yaml --env dev --backend aws|firebase --out <file>
  flags audit      --registry flags/flags.yaml

  events validate  --registry analytics/events.yaml
  events codegen   --registry analytics/events.yaml --out lib/generated/events.g.dart [--check]

  tokens validate  --tokens design/tokens.json
  tokens codegen   --tokens design/tokens.json --out lib/generated/design_tokens.g.dart [--check]

--check regenerates in memory and fails if the file on disk differs. Run it in
CI so a registry edit without a regeneration cannot merge.

Exit codes: 0 ok · 1 errors found · 2 bad usage.
''';

/// Signals an exit without a stack trace. Usage mistakes and validation
/// failures are expected outcomes of a CLI, not crashes.
class ExitWithCode implements Exception {
  ExitWithCode(this.code);

  final int code;
}

Future<int> run(List<String> argv) async {
  if (argv.isEmpty || argv.first == '--help' || argv.first == '-h') {
    stdout.write(_usage);
    return argv.isEmpty ? 2 : 0;
  }
  if (argv.length < 2) {
    stderr.writeln('Expected a group and an action, e.g. "flags validate".\n');
    stderr.write(_usage);
    return 2;
  }

  final group = argv[0];
  final action = argv[1];
  final rest = argv.sublist(2);

  try {
    return switch ('$group $action') {
      'flags validate' => _flagsValidate(rest),
      'flags codegen' => _flagsCodegen(rest),
      'flags render' => _flagsRender(rest),
      'flags audit' => _flagsAudit(rest),
      'events validate' => _eventsValidate(rest),
      'events codegen' => _eventsCodegen(rest),
      'tokens validate' => _tokensValidate(rest),
      'tokens codegen' => _tokensCodegen(rest),
      _ => _unknown(group, action),
    };
  } on ExitWithCode catch (e) {
    return e.code;
  } on RegistryException catch (e) {
    stderr.writeln('error: $e');
    return 1;
  } on FormatException catch (e) {
    stderr.writeln('error: ${e.message}');
    return 2;
  }
}

int _unknown(String group, String action) {
  stderr.writeln('Unknown command "$group $action".\n');
  stderr.write(_usage);
  return 2;
}

// ---------------------------------------------------------------------------
// flags
// ---------------------------------------------------------------------------

ArgParser _flagsParser({bool out = false, bool render = false}) {
  final parser = ArgParser()
    ..addOption('registry', defaultsTo: 'flags/flags.yaml')
    ..addOption('environments',
        defaultsTo: 'dev,staging,prod',
        help: 'Environment names the registry may mention.')
    ..addFlag('strict-expiry',
        negatable: false,
        help: 'Treat an expired flag as an error rather than a warning.');
  if (out) {
    parser
      ..addOption('out', mandatory: true)
      ..addFlag('check', negatable: false);
  }
  if (render) {
    parser
      ..addOption('env', mandatory: true)
      ..addOption('backend', allowed: ['aws', 'firebase'], defaultsTo: 'aws')
      ..addOption('out', mandatory: true);
  }
  return parser;
}

typedef ParsedFlags = ({FlagRegistryParser parser, FlagRegistry registry});

ParsedFlags _parseFlags(ArgResults args) {
  final path = args['registry'] as String;
  final environments = (args['environments'] as String)
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  final parser = FlagRegistryParser(environments: environments);
  return (parser: parser, registry: parser.parse(_read(path), path));
}

int _flagsValidate(List<String> argv) {
  final args = _flagsParser().parse(argv);
  final parsed = _parseFlags(args);

  _applyExpiry(parsed, strict: args['strict-expiry'] as bool);
  return _report(parsed.parser.diagnostics, 'flags', parsed.registry.flags.length);
}

int _flagsAudit(List<String> argv) {
  final args = _flagsParser().parse(argv);
  final registry = _parseFlags(args).registry;

  final expired = registry.flags.where((f) => f.isExpired).toList();
  final undated = registry.flags.where((f) => f.expires == null).toList();

  stdout.writeln('${registry.flags.length} flags in ${registry.sourcePath}');
  stdout.writeln('  ${expired.length} past their expiry date');
  stdout.writeln('  ${undated.length} with no expiry date');

  if (expired.isNotEmpty) {
    stdout.writeln('\nPast due — these should have been removed:');
    for (final flag in expired) {
      final date = flag.expires!.toIso8601String().split('T').first;
      stdout.writeln('  ${flag.key.padRight(32)} expired $date  '
          'owner: ${flag.owner ?? 'nobody'}');
    }
  }

  if (undated.isNotEmpty) {
    stdout.writeln('\nNo expiry date:');
    for (final flag in undated) {
      stdout.writeln('  ${flag.key.padRight(32)} owner: ${flag.owner ?? 'nobody'}');
    }
  }

  // Read-only: reports, never fails. Flag debt is a standing conversation, not
  // a reason to block tonight's release.
  return 0;
}

int _flagsCodegen(List<String> argv) {
  final args = _flagsParser(out: true).parse(argv);
  final parsed = _parseFlags(args);
  _applyExpiry(parsed, strict: args['strict-expiry'] as bool);

  final diagnostics = parsed.parser.diagnostics;
  if (diagnostics.hasErrors) {
    return _report(diagnostics, 'flags', parsed.registry.flags.length);
  }

  _printWarnings(diagnostics);
  return _emit(
    generateFlagsDart(parsed.registry, command: 'make flags-codegen'),
    args['out'] as String,
    check: args['check'] as bool,
  );
}

int _flagsRender(List<String> argv) {
  final args = _flagsParser(render: true).parse(argv);
  final parsed = _parseFlags(args);

  final environment = args['env'] as String;
  final registry = parsed.registry;
  final diagnostics = parsed.parser.diagnostics;

  if (diagnostics.hasErrors) {
    return _report(diagnostics, 'flags', registry.flags.length);
  }
  _printWarnings(diagnostics);

  final backend = args['backend'] as String;
  final String rendered;

  if (backend == 'firebase') {
    final result = renderFirebaseTemplate(registry, environment);
    if (result.diagnostics.hasErrors) {
      return _report(result.diagnostics, 'flags', registry.flags.length);
    }
    rendered = result.json;
  } else {
    rendered = renderAwsDocument(registry, environment);
  }

  return _emit(rendered, args['out'] as String, check: false);
}

void _applyExpiry(ParsedFlags parsed, {required bool strict}) {
  for (final flag in parsed.registry.flags.where((f) => f.isExpired)) {
    final date = flag.expires!.toIso8601String().split('T').first;
    final message =
        'expired on $date and is still in the registry (owner: '
        '${flag.owner ?? 'nobody'}). Remove the flag and the branch it guards.';
    if (strict) {
      parsed.parser.diagnostics.error(message, location: 'flags "${flag.key}"');
    } else {
      parsed.parser.diagnostics.warning(message, location: 'flags "${flag.key}"');
    }
  }
}

// ---------------------------------------------------------------------------
// events
// ---------------------------------------------------------------------------

ArgParser _eventsParser({bool out = false}) {
  final parser = ArgParser()
    ..addOption('registry', defaultsTo: 'analytics/events.yaml');
  if (out) {
    parser
      ..addOption('out', mandatory: true)
      ..addFlag('check', negatable: false);
  }
  return parser;
}

int _eventsValidate(List<String> argv) {
  final args = _eventsParser().parse(argv);
  final path = args['registry'] as String;
  final parser = EventRegistryParser();
  final registry = parser.parse(_read(path), path);

  return _report(parser.diagnostics, 'events', registry.events.length);
}

int _eventsCodegen(List<String> argv) {
  final args = _eventsParser(out: true).parse(argv);
  final path = args['registry'] as String;
  final parser = EventRegistryParser();
  final registry = parser.parse(_read(path), path);

  if (parser.diagnostics.hasErrors) {
    return _report(parser.diagnostics, 'events', registry.events.length);
  }
  _printWarnings(parser.diagnostics);

  return _emit(
    generateEventsDart(registry, command: 'make analytics-codegen'),
    args['out'] as String,
    check: args['check'] as bool,
  );
}

// ---------------------------------------------------------------------------
// tokens
// ---------------------------------------------------------------------------

ArgParser _tokensParser({bool out = false}) {
  final parser = ArgParser()
    ..addOption('tokens', defaultsTo: 'design/tokens.json');
  if (out) {
    parser
      ..addOption('out', mandatory: true)
      ..addFlag('check', negatable: false);
  }
  return parser;
}

int _tokensValidate(List<String> argv) {
  final args = _tokensParser().parse(argv);
  final path = args['tokens'] as String;
  final parser = TokenParser();
  final tokens = parser.parse(_read(path), path);

  return _report(parser.diagnostics, 'colour tokens', tokens.colors.length);
}

int _tokensCodegen(List<String> argv) {
  final args = _tokensParser(out: true).parse(argv);
  final path = args['tokens'] as String;
  final parser = TokenParser();
  final tokens = parser.parse(_read(path), path);

  if (parser.diagnostics.hasErrors) {
    return _report(parser.diagnostics, 'colour tokens', tokens.colors.length);
  }
  _printWarnings(parser.diagnostics);

  return _emit(
    generateTokensDart(tokens, command: 'make design-tokens'),
    args['out'] as String,
    check: args['check'] as bool,
  );
}

// ---------------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------------

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw RegistryException('$path: no such file');
  }
  return file.readAsStringSync();
}

/// Writes [content] to [path], or — with [check] — compares and fails.
int _emit(String content, String path, {required bool check}) {
  final file = File(path);

  if (check) {
    if (!file.existsSync()) {
      stderr.writeln('error: $path does not exist. Run the generator.');
      return 1;
    }
    if (file.readAsStringSync() != content) {
      stderr.writeln(
        'error: $path is out of date with its registry.\n'
        '       Regenerate it and commit the result.',
      );
      return 1;
    }
    stdout.writeln('$path is up to date.');
    return 0;
  }

  file.parent.createSync(recursive: true);

  // Skip an identical write so the file's mtime does not churn and invalidate
  // build caches on every run.
  if (file.existsSync() && file.readAsStringSync() == content) {
    stdout.writeln('$path unchanged.');
    return 0;
  }

  file.writeAsStringSync(content);
  stdout.writeln('wrote $path');
  return 0;
}

int _report(Diagnostics diagnostics, String noun, int count) {
  if (diagnostics.isEmpty) {
    stdout.writeln('$count $noun, no problems found.');
    return 0;
  }

  for (final diagnostic in diagnostics.sorted) {
    final sink = diagnostic.severity == Severity.error ? stderr : stdout;
    sink.writeln(diagnostic);
  }

  final errors = diagnostics.errors.length;
  final warnings = diagnostics.warnings.length;
  stdout.writeln('\n$count $noun · $errors error(s), $warnings warning(s)');

  return diagnostics.hasErrors ? 1 : 0;
}

void _printWarnings(Diagnostics diagnostics) {
  for (final diagnostic in diagnostics.warnings) {
    stdout.writeln(diagnostic);
  }
}
