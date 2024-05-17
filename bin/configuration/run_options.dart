import 'package:args/args.dart';

class RunOptions {
  final bool showHelp;
  final String confFile;
  final ArgParser parser;

  RunOptions(this.confFile, this.parser, this.showHelp);

  factory RunOptions.fromArgs(List<String> args) {
    final parser = ArgParser();
    parser.addOption('conf', abbr: 'c', mandatory: true, help: 'Configuration file');
    parser.addFlag('help', abbr: 'h', help: 'Display usage');
    final String confFile = parser.parse(args).option("conf") ?? '';
    final bool showHelp = parser.parse(args).flag("help");
    return RunOptions(confFile, parser, showHelp);
  }

  void usage() {
    print(parser.usage);
  }
}
