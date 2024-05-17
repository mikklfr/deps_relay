import 'dart:convert';
import 'dart:io';

import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

import '../modules/flutter/flutter.dart';

part 'configuration.g.dart';

@JsonSerializable()
class ServerConfiguration {
  final String baseUrl;
  final int port;

  ServerConfiguration({
    required this.baseUrl,
    required this.port,
  });

  factory ServerConfiguration.fromJson(Map<String, dynamic> json) {
    return ServerConfiguration(
      baseUrl: json['baseUrl'],
      port: json['port'],
    );
  }
}

@JsonSerializable(constructor: '_')
@CopyWith(constructor: '_')
class Configuration {
  final ServerConfiguration server;
  final FlutterModuleConfiguration flutter;

  Configuration._({
    required this.server,
    required this.flutter,
  });

  static Future<Configuration> fromFile(String? configurationFile) async {
    return Configuration.fromJson(
      jsonDecode(
        await File(configurationFile ?? '.conf.json').readAsString(),
      ),
    );
  }

  factory Configuration.fromJson(Map<String, dynamic> json) => _$ConfigurationFromJson(json);

  Map<String, dynamic> toJson() => _$ConfigurationToJson(this);
}
