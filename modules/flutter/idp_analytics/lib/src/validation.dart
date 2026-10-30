/// Runtime parameter checking.
///
/// Only structure is checked here — that values are flat and of a type every
/// vendor accepts. Naming rules and per-vendor limits (GA4's 40-character
/// event names, 25 parameters, reserved `firebase_`/`google_`/`ga_` prefixes)
/// are enforced at build time by `idp_codegen validate`, because a limit that
/// belongs to one vendor should not silently drop events destined for another.
class ParameterError {
  const ParameterError(this.key, this.message);

  final String key;
  final String message;

  @override
  String toString() => 'parameter "$key": $message';
}

/// Returns the problems with [parameters]; empty means valid.
List<ParameterError> validateParameters(Map<String, Object?> parameters) {
  final errors = <ParameterError>[];
  for (final entry in parameters.entries) {
    final value = entry.value;
    if (value == null) continue; // Dropped, not an error — see sanitize below.
    if (value is String || value is num || value is bool) continue;
    errors.add(ParameterError(
      entry.key,
      'type ${value.runtimeType} is not supported; use String, num or bool '
      '(encode structured values as JSON at the call site)',
    ));
  }
  return errors;
}

/// Drops nulls. Null parameters are common — an optional field that happened
/// not to be set — and forwarding them makes vendors behave inconsistently
/// (some store the literal string "null"), so they are removed rather than
/// reported as an error.
Map<String, Object?> sanitizeParameters(Map<String, Object?> parameters) {
  if (!parameters.values.any((v) => v == null)) return parameters;
  return {
    for (final e in parameters.entries)
      if (e.value != null) e.key: e.value,
  };
}
