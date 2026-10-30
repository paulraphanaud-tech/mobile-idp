import 'dart:io';

import 'package:idp_codegen/src/runner.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await run(arguments);
}
