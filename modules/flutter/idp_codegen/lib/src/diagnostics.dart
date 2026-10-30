/// A problem found in a registry.
///
/// Warnings and errors are distinguished because these run in CI: an error
/// means the registry is wrong and the build should stop, a warning means the
/// registry is *aging* — a flag past its expiry, an event with no owner —
/// which should be visible without blocking a release at 6pm.
enum Severity { warning, error }

class Diagnostic {
  Diagnostic(this.severity, this.message, {this.location});

  Diagnostic.error(this.message, {this.location}) : severity = Severity.error;

  Diagnostic.warning(this.message, {this.location})
      : severity = Severity.warning;

  final Severity severity;
  final String message;

  /// Where in the registry, e.g. `flags[3] "new_checkout"`.
  final String? location;

  @override
  String toString() {
    final label = severity == Severity.error ? 'error' : 'warning';
    return location == null
        ? '$label: $message'
        : '$label: $location: $message';
  }
}

class Diagnostics {
  final List<Diagnostic> entries = [];

  void error(String message, {String? location}) =>
      entries.add(Diagnostic.error(message, location: location));

  void warning(String message, {String? location}) =>
      entries.add(Diagnostic.warning(message, location: location));

  void addAll(Diagnostics other) => entries.addAll(other.entries);

  Iterable<Diagnostic> get errors =>
      entries.where((d) => d.severity == Severity.error);

  Iterable<Diagnostic> get warnings =>
      entries.where((d) => d.severity == Severity.warning);

  bool get hasErrors => errors.isNotEmpty;

  bool get isEmpty => entries.isEmpty;

  /// Errors first: in a long list the blocking problems should be the ones
  /// still on screen after the scroll.
  List<Diagnostic> get sorted => [...errors, ...warnings];
}

/// Thrown for problems that stop parsing entirely — a missing file, YAML that
/// does not parse. Per-entry problems are [Diagnostic]s instead, so one bad
/// flag does not hide the other nine.
class RegistryException implements Exception {
  RegistryException(this.message);

  final String message;

  @override
  String toString() => message;
}
