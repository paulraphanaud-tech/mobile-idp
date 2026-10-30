import 'flag.dart';

/// The outcome of evaluating a flag, including where the value came from.
///
/// Attribution is the point. "Why is this flag on for me?" is the single most
/// common question about any flag system, and a bare `bool` cannot answer it —
/// which is why the debug panel and the exposure hook both take this rather
/// than the value alone.
class FlagResolution<T extends Object> {
  const FlagResolution({
    required this.flag,
    required this.value,
    required this.sourceId,
    required this.raw,
    this.decodeFailed = false,
  });

  final Flag<T> flag;
  final T value;

  /// Id of the [FlagSource] that supplied the value, or null when nothing did
  /// and [flag]'s bundled default was used.
  final String? sourceId;

  /// What the source actually returned, before decoding. Null when defaulted.
  final Object? raw;

  /// True when a source held a value but it could not be decoded to [T] — a
  /// string where a number was expected, a value outside `allowedValues`. The
  /// default was used instead and the error hook was called.
  final bool decodeFailed;

  bool get isDefault => sourceId == null;

  /// True when a local override won, i.e. this device is not seeing what the
  /// backend would give it.
  bool get isOverridden => sourceId == 'override';

  @override
  String toString() => 'FlagResolution(${flag.key} = $value '
      'from ${sourceId ?? 'default'}${decodeFailed ? ', decode failed' : ''})';
}
