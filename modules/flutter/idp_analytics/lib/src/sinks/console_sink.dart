import '../consent.dart';
import '../event.dart';
import '../sink.dart';

/// Prints to a callback (defaults to `print`). The default sink in debug
/// builds, so that "is this event firing, with what payload?" is answerable
/// without opening a vendor dashboard that lags by hours.
class ConsoleAnalyticsSink extends AnalyticsSinkBase {
  ConsoleAnalyticsSink({
    this.prefix = '[analytics]',
    void Function(String line)? output,
  }) : _output = output ?? print;

  final String prefix;
  final void Function(String) _output;

  @override
  String get id => 'console';

  @override
  Future<void> logEvent(AnalyticsEvent event) async {
    final params = event.parameters;
    _output(params.isEmpty
        ? '$prefix event ${event.name}'
        : '$prefix event ${event.name} $params');
  }

  @override
  Future<void> logScreenView(ScreenView screen) async {
    _output('$prefix screen ${screen.name}'
        '${screen.className == null ? '' : ' (${screen.className})'}');
  }

  @override
  Future<void> setUserId(String? userId) async =>
      _output('$prefix userId ${userId ?? '<cleared>'}');

  @override
  Future<void> setUserProperty(String name, String? value) async =>
      _output('$prefix userProperty $name=${value ?? '<cleared>'}');

  @override
  Future<void> setConsent(Consent consent) async =>
      _output('$prefix consent $consent');

  @override
  Future<void> reset() async => _output('$prefix reset');
}
