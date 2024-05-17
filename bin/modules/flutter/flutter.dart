import 'dart:async';

import 'package:alfred/alfred.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:get_it/get_it.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../configuration/configuration.dart';
import 'auth/user.dart';
import 'input/http.dart';
import 'sources/git/git.dart';
import 'sources/hosted/hosted.dart';
import 'sources/local/local.dart';

part 'flutter.g.dart';

@CopyWith()
@JsonSerializable()
class FlutterModuleStorageConfiguration {
  final String s3Bucket;
  final String s3Region;
  final String s3Endpoint;
  final String s3AccessKey;
  final String s3SecretKey;

  FlutterModuleStorageConfiguration({
    required this.s3Bucket,
    required this.s3Region,
    required this.s3Endpoint,
    required this.s3AccessKey,
    required this.s3SecretKey,
  });

  factory FlutterModuleStorageConfiguration.fromJson(Map<String, dynamic> json) =>
      _$FlutterModuleStorageConfigurationFromJson(json);

  Map<String, dynamic> toJson() => _$FlutterModuleStorageConfigurationToJson(this);
}

@JsonSerializable()
class FlutterModuleDatabaseConfiguration {
  final String path;
  final String? name;

  FlutterModuleDatabaseConfiguration({
    required this.path,
    this.name,
  });

  factory FlutterModuleDatabaseConfiguration.fromJson(Map<String, dynamic> json) =>
      _$FlutterModuleDatabaseConfigurationFromJson(json);

  Map<String, dynamic> toJson() => _$FlutterModuleDatabaseConfigurationToJson(this);
}

@JsonSerializable()
@CopyWith()
class FlutterModuleConfiguration {
  final bool storePackages;
  final bool useLocalPackages;
  final bool useHostedUpstreamPackages;
  final bool useGitPackages;
  final bool requiresAuthentication;
  final bool enableDebugRoutes;

  final FlutterModuleDatabaseConfiguration database;
  final FlutterModuleStorageConfiguration storage;

  final List<HostedRepositoryUpstream> hostedUpstreams;
  final List<GitRepositoryDartPackageDefinition> gitUpstreams;

  final List<UserDefinition> users;

  factory FlutterModuleConfiguration.fromJson(Map<String, dynamic> json) => _$FlutterModuleConfigurationFromJson(json);

  FlutterModuleConfiguration({
    required this.storePackages,
    required this.useLocalPackages,
    required this.useHostedUpstreamPackages,
    required this.useGitPackages,
    required this.database,
    required this.storage,
    required this.hostedUpstreams,
    required this.gitUpstreams,
    required this.users,
    required this.requiresAuthentication,
    required this.enableDebugRoutes,
  });

  Map<String, dynamic> toJson() => _$FlutterModuleConfigurationToJson(this);
}

class FlutterModule {
  final Alfred alfred;
  FlutterModuleConfiguration configuration;
  Configuration serverConfiguration;

  FlutterModule._({
    required this.alfred,
    required this.configuration,
    required this.serverConfiguration,
  });

  static Future<FlutterModule> create({
    required Alfred alfred,
    required Configuration configuration,
  }) async {
    final getIt = GetIt.instance;

    final flutterConfiguration = configuration.flutter;

    final FlutterStorage storage = await FlutterStorage.init(
      bucketName: flutterConfiguration.storage.s3Bucket,
      databasePath: flutterConfiguration.database.path,
      databaseName: flutterConfiguration.database.name,
      s3Region: flutterConfiguration.storage.s3Region,
      s3Endpoint: flutterConfiguration.storage.s3Endpoint,
      s3AccessKey: flutterConfiguration.storage.s3AccessKey,
      s3SecretKey: flutterConfiguration.storage.s3SecretKey,
    );

    getIt.registerSingleton<FlutterModuleConfiguration>(flutterConfiguration);
    getIt.registerSingleton<HostedRepositoryUpstreams>(HostedRepositoryUpstreams(flutterConfiguration.hostedUpstreams));
    getIt.registerSingleton<GitRepositoryUpstreams>(GitRepositoryUpstreams(flutterConfiguration.gitUpstreams));
    getIt.registerSingleton<FlutterStorage>(storage);

    final instance =
        FlutterModule._(alfred: alfred, configuration: flutterConfiguration, serverConfiguration: configuration);
    final http = FlutterHttpRouting(alfred, instance);
    await http.init();

    return instance;
  }
}
