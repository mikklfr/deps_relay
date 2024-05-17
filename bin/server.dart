import 'package:alfred/alfred.dart';

import 'configuration/configuration.dart';
import 'configuration/run_options.dart';
import 'modules/flutter/flutter.dart';

final alfred = Alfred();

void main(List<String> args) async {
  try {
    final options = RunOptions.fromArgs(args);

    if (options.showHelp || options.confFile.isEmpty) {
      options.usage();
      return;
    }

    final configuration = await Configuration.fromFile(options.confFile);
    await FlutterModule.create(alfred: alfred, configuration: configuration);
    await alfred.listen(configuration.server.port);
  } catch (e) {
    print(e);
  }
}
