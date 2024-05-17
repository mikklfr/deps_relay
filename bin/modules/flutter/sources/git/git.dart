import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:json_annotation/json_annotation.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

import '../dart_package.dart';
import 'utils.dart';

part 'git.g.dart';

class GitRepositoryUpstreams {
  List<GitRepositoryDartPackageDefinition> packages;

  GitRepositoryUpstreams(this.packages);

  Future<GitRepositoryDartPackage?> getPackage(String package, String version) async =>
      (await searchPackages(package)).where((element) => element.version == version).firstOrNull;

  Future<List<GitRepositoryDartPackage>> searchPackages(String package) async {
    final matching = packages.where((element) => element.name == package).toList();
    List<GitRepositoryDartPackage> result = [];
    for (var package in matching) {
      if (package.sshHost != null) {
        addKnownHost(package.sshHost!);
      }

      final List<VersionPubspecPair> gitResults = await readRepository(package);

      for (var gitResult in gitResults) {
        String rewriteVersion = gitResult.version;
        rewriteVersion = removeOrigin(rewriteVersion);
        rewriteVersion = matchWithCompatibleVersion(rewriteVersion);

        if (rewriteVersion.isNotEmpty) {
          result.add(GitRepositoryDartPackage(
            package.name,
            rewriteVersion,
            gitResult.pubspec,
            package,
            removeOrigin(gitResult.version),
            gitResult.sshHost,
          ));
        }
      }
    }
    return result;
  }

  Future<Uint8List> generateTarball(GitRepositoryDartPackage gitRepositoryUpstreamsPackage) async {
    final tmp = await cloneRepo(
      gitRepositoryUpstreamsPackage.definition.url,
      gitRepositoryUpstreamsPackage.branch,
      gitRepositoryUpstreamsPackage.sshHost,
    );
    String finalPath;
    if (gitRepositoryUpstreamsPackage.definition.subPath != null) {
      finalPath = "$tmp/${gitRepositoryUpstreamsPackage.definition.subPath}";
    } else {
      finalPath = tmp;
    }
    // ensure pubspec is valid
    final pubspec = await File("$finalPath/pubspec.yaml").readAsString();
    final Map<String, dynamic> pubspecMap = {};
    pubspecMap.addAll(jsonDecode(jsonEncode(loadYaml(pubspec))));
    pubspecMap['version'] = gitRepositoryUpstreamsPackage.version;
    final txt = YamlWriter().write(pubspecMap);
    await File("$finalPath/pubspec.yaml").writeAsString(txt);

    // create the tarball
    final content = await tarDirectory(tmp, finalPath, gitRepositoryUpstreamsPackage.definition.subPath);
    await Directory(tmp).delete(recursive: true);
    return content;
  }
}

class GitRepository {
  final String url;
  final String ref;

  GitRepository({required this.url, required this.ref});
}

class GitRepositoryDartPackage extends DartPackage {
  @override
  final String name;
  @override
  final String version;
  @override
  final String pubspec;
  @override
  final String? sha256 = null;
  final String branch;
  final String? sshHost;

  final GitRepositoryDartPackageDefinition definition;

  GitRepositoryDartPackage(this.name, this.version, this.pubspec, this.definition, this.branch, this.sshHost);
}

@JsonSerializable()
class GitRepositoryDartPackageDefinition {
  final String name;
  final String url;
  final String? subPath;
  final String? sshHost;

  GitRepositoryDartPackageDefinition({
    required this.name,
    required this.url,
    this.subPath,
    this.sshHost,
  });

  factory GitRepositoryDartPackageDefinition.fromJson(Map<String, dynamic> json) =>
      _$GitRepositoryDartPackageDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$GitRepositoryDartPackageDefinitionToJson(this);
}

class VersionPubspecPair {
  final String version;
  final String pubspec;
  final String? sshHost;

  VersionPubspecPair(this.version, this.pubspec, this.sshHost);
}
