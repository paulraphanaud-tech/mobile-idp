import 'dart:convert';

/// A flag's declared type. Carried at runtime so that sources which store
/// everything as text (Remote Config does) can coerce correctly, and so the
/// debug panel can render the right editor.
enum FlagType { boolean, string, integer, double, json }

/// A typed flag definition.
///
/// Flags are **declared**, not invented at the call site. `idp_codegen`
/// generates one `static const` per entry in `flags/flags.yaml`, which is what
/// makes a flag greppable, renameable, and impossible to misspell — and what
/// lets the platform detect a flag that exists in code but not in the registry
/// (or the reverse) at build time rather than in production.
sealed class Flag<T extends Object> {
  const Flag({
    required this.key,
    required this.defaultValue,
    this.description,
    this.owner,
  });

  /// The key as it appears in the registry and in the backend. Snake case.
  final String key;

  /// Returned when no source has an opinion, when a source returns something
  /// undecodable, and — importantly — on first run before any network call has
  /// completed. This value ships in the binary, so it must be the safe choice:
  /// for a kill switch that means "feature on, kill switch not pulled".
  final T defaultValue;

  final String? description;

  /// Team or person accountable for removing this flag. Surfaced by
  /// `make flags-audit` when a flag is past its expiry.
  final String? owner;

  FlagType get type;

  /// Converts a source's raw value to [T], or null if it cannot.
  ///
  /// Returning null rather than throwing is deliberate: a malformed remote
  /// value must degrade to [defaultValue], never take the app down. The facade
  /// reports the failure through its error hook.
  T? decode(Object? raw);

  @override
  String toString() => '$runtimeType($key)';
}

class BoolFlag extends Flag<bool> {
  const BoolFlag({
    required super.key,
    required super.defaultValue,
    super.description,
    super.owner,
  });

  @override
  FlagType get type => FlagType.boolean;

  @override
  bool? decode(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      // Remote Config hands back strings for everything, and its own
      // asBool() accepts this set. Matching it keeps a value typed "true" in
      // one backend and `true` in another from behaving differently.
      final v = raw.trim().toLowerCase();
      if (const ['true', 't', 'yes', 'y', 'on', '1'].contains(v)) return true;
      if (const ['false', 'f', 'no', 'n', 'off', '0', ''].contains(v)) return false;
    }
    return null;
  }
}

class StringFlag extends Flag<String> {
  const StringFlag({
    required super.key,
    required super.defaultValue,
    super.description,
    super.owner,
    this.allowedValues,
  });

  /// When set, a remote value outside this set is rejected and the default is
  /// used. Stops a typo in a backend console from putting the app into a state
  /// the code has no branch for.
  final List<String>? allowedValues;

  @override
  FlagType get type => FlagType.string;

  @override
  String? decode(Object? raw) {
    final value = switch (raw) {
      String s => s,
      num n => n.toString(),
      bool b => b.toString(),
      _ => null,
    };
    if (value == null) return null;
    final allowed = allowedValues;
    if (allowed != null && !allowed.contains(value)) return null;
    return value;
  }
}

class IntFlag extends Flag<int> {
  const IntFlag({
    required super.key,
    required super.defaultValue,
    super.description,
    super.owner,
    this.min,
    this.max,
  });

  final int? min;
  final int? max;

  @override
  FlagType get type => FlagType.integer;

  @override
  int? decode(Object? raw) {
    final value = switch (raw) {
      int i => i,
      num n => n.toInt(),
      String s => int.tryParse(s.trim()),
      _ => null,
    };
    if (value == null) return null;
    if (min != null && value < min!) return null;
    if (max != null && value > max!) return null;
    return value;
  }
}

class DoubleFlag extends Flag<double> {
  const DoubleFlag({
    required super.key,
    required super.defaultValue,
    super.description,
    super.owner,
    this.min,
    this.max,
  });

  final double? min;
  final double? max;

  @override
  FlagType get type => FlagType.double;

  @override
  double? decode(Object? raw) {
    final value = switch (raw) {
      num n => n.toDouble(),
      String s => double.tryParse(s.trim()),
      _ => null,
    };
    if (value == null) return null;
    if (min != null && value < min!) return null;
    if (max != null && value > max!) return null;
    return value;
  }
}

/// A structured flag: remote config as a small JSON document.
///
/// Useful for values that travel together — a set of retry parameters, a
/// tiered pricing table. [parse] must return null for anything it does not
/// recognise, so a half-edited document falls back to the default rather than
/// half-applying.
class JsonFlag<T extends Object> extends Flag<T> {
  const JsonFlag({
    required super.key,
    required super.defaultValue,
    required this.parse,
    super.description,
    super.owner,
  });

  final T? Function(Map<String, Object?> json) parse;

  @override
  FlagType get type => FlagType.json;

  @override
  T? decode(Object? raw) {
    Map<String, Object?>? map;
    if (raw is Map<String, Object?>) {
      map = raw;
    } else if (raw is Map) {
      map = raw.map((k, v) => MapEntry(k.toString(), v));
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          map = decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        return null;
      }
    }
    if (map == null) return null;
    try {
      return parse(map);
    } catch (_) {
      return null;
    }
  }
}
