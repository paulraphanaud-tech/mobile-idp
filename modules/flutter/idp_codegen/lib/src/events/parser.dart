import '../diagnostics.dart';
import '../naming.dart';
import '../yaml_util.dart';
import 'model.dart';

/// GA4 rejects these outright — an event using one is silently never recorded.
const reservedEventPrefixes = ['firebase_', 'google_', 'ga_'];

/// GA4 collects these itself. Sending your own would mix hand-rolled data into
/// a series the platform also writes, and there is no way to separate them
/// again afterwards.
const reservedEventNames = {
  'ad_activeview', 'ad_click', 'ad_exposure', 'ad_impression', 'ad_query',
  'ad_reward', 'adunit_exposure', 'app_background', 'app_clear_data',
  'app_exception', 'app_remove', 'app_store_refund', 'app_store_subscription_cancel',
  'app_store_subscription_convert', 'app_store_subscription_renew', 'app_update',
  'app_upgrade', 'dynamic_link_app_open', 'dynamic_link_app_update',
  'dynamic_link_first_open', 'error', 'first_open', 'first_visit',
  'in_app_purchase', 'notification_dismiss', 'notification_foreground',
  'notification_open', 'notification_receive', 'os_update', 'session_start',
  'user_engagement',
};

/// GA4's limits. The strictest of the common backends, and the one this
/// platform ships by default, so the registry is held to them — an event that
/// breaks them is dropped or truncated in the field with no error anywhere.
const maxEventNameLength = 40;
const maxParameterNameLength = 40;
const maxParametersPerEvent = 25;

class EventRegistryParser {
  final diagnostics = Diagnostics();

  EventRegistry parse(String source, String path) {
    final doc = parseYamlDocument(source, path);
    final raw = doc['events'];

    if (raw == null) {
      throw RegistryException('$path: missing top-level "events:" list');
    }
    if (raw is! List<Object?>) {
      throw RegistryException('$path: "events" must be a list');
    }

    final events = <EventDefinition>[];
    final seen = <String, int>{};

    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is! Map<String, Object?>) {
        diagnostics.error('each event must be a mapping', location: 'events[$i]');
        continue;
      }

      final name = entry['name'];
      if (name is! String || name.isEmpty) {
        diagnostics.error('missing required "name"', location: 'events[$i]');
        continue;
      }

      final location = 'events[$i] "$name"';

      if (seen.containsKey(name)) {
        diagnostics.error(
          'duplicate event, already defined at events[${seen[name]}]',
          location: location,
        );
        continue;
      }
      seen[name] = i;

      _validateEventName(name, location);

      events.add(EventDefinition(
        name: name,
        description: _requireText(entry['description'], 'description', location),
        owner: _requireText(entry['owner'], 'owner', location),
        parameters: _parseParameters(entry['parameters'], location),
      ));
    }

    return EventRegistry(events: events, sourcePath: path);
  }

  void _validateEventName(String name, String location) {
    if (!isSnakeCase(name)) {
      diagnostics.error(
        'event name must be snake_case — it becomes a GA4 event name and a '
        'BigQuery value verbatim',
        location: location,
      );
    }
    if (name.length > maxEventNameLength) {
      diagnostics.error(
        'event name is ${name.length} characters; GA4 allows '
        '$maxEventNameLength and rejects the event beyond that',
        location: location,
      );
    }
    for (final prefix in reservedEventPrefixes) {
      if (name.startsWith(prefix)) {
        diagnostics.error(
          '"$prefix" is reserved by GA4; events using it are silently never '
          'recorded',
          location: location,
        );
      }
    }
    if (reservedEventNames.contains(name)) {
      diagnostics.error(
        '"$name" is collected automatically by GA4; sending your own mixes '
        'hand-rolled data into a series the platform also writes, and the two '
        'cannot be separated afterwards',
        location: location,
      );
    }
    if (dartReservedWords.contains(toLowerCamel(name))) {
      diagnostics.error(
        'generates the Dart keyword "${toLowerCamel(name)}"; rename the event',
        location: location,
      );
    }
  }

  List<EventParameter> _parseParameters(Object? raw, String location) {
    if (raw == null) return const [];
    if (raw is! List<Object?>) {
      diagnostics.error('"parameters" must be a list', location: location);
      return const [];
    }

    if (raw.length > maxParametersPerEvent) {
      diagnostics.error(
        '${raw.length} parameters; GA4 accepts $maxParametersPerEvent per '
        'event and drops the rest without reporting it',
        location: location,
      );
    }

    final parameters = <EventParameter>[];
    final seen = <String>{};

    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      final paramLocation = '$location parameters[$i]';

      if (entry is! Map<String, Object?>) {
        diagnostics.error('each parameter must be a mapping', location: paramLocation);
        continue;
      }

      final name = entry['name'];
      if (name is! String || name.isEmpty) {
        diagnostics.error('missing required "name"', location: paramLocation);
        continue;
      }
      if (!seen.add(name)) {
        diagnostics.error('duplicate parameter "$name"', location: paramLocation);
        continue;
      }
      if (!isSnakeCase(name)) {
        diagnostics.error('parameter name must be snake_case', location: paramLocation);
      }
      if (name.length > maxParameterNameLength) {
        diagnostics.error(
          'parameter name is ${name.length} characters; GA4 allows '
          '$maxParameterNameLength',
          location: paramLocation,
        );
      }

      final type = ParameterType.fromYaml(entry['type'] as String?);
      if (type == null) {
        diagnostics.error(
          'missing or unknown "type"; expected one of '
          '${ParameterType.values.map((t) => t.yamlName).join(', ')}',
          location: paramLocation,
        );
        continue;
      }

      final allowed = entry['allowed_values'];
      List<String>? allowedValues;
      if (allowed != null) {
        if (type != ParameterType.string) {
          diagnostics.error(
            '"allowed_values" applies only to string parameters',
            location: paramLocation,
          );
        } else if (allowed is! List<Object?>) {
          diagnostics.error('"allowed_values" must be a list', location: paramLocation);
        } else {
          allowedValues = allowed.map((v) => v.toString()).toList();
        }
      }

      parameters.add(EventParameter(
        name: name,
        type: type,
        required: entry['required'] == true,
        description: entry['description'] as String?,
        allowedValues: allowedValues,
      ));
    }

    return parameters;
  }

  String? _requireText(Object? value, String field, String location) {
    if (value is String && value.isNotEmpty) return value;
    diagnostics.warning(
      'no "$field"'
      '${field == 'description' ? ' — an event nobody can explain is an event '
          'nobody will trust in six months' : ''}',
      location: location,
    );
    return null;
  }
}
