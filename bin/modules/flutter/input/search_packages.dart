import 'dart:convert';

import 'package:get_it/get_it.dart';

import '../flutter.dart';
import '../output/response.dart';
import '../sources/dart_package.dart';
import '../sources/git/git.dart';
import '../sources/hosted/hosted.dart';
import '../sources/local/local.dart';

Future<List<T>> fetchPackages<T>(bool usePackages, Future<List<T>> Function() fetchFunction) async {
  try {
    return usePackages ? await fetchFunction() : [];
  } catch (e) {
    return [];
  }
}

final getIt = GetIt.instance;

Future searchPackages(String queryPackage, res, FlutterModule flutterModule) async {
  final FlutterModuleConfiguration configuration = getIt();
  final FlutterStorage storage = getIt();
  final HostedRepositoryUpstreams hostedRepositoryUpstreams = getIt();
  final GitRepositoryUpstreams gitRepositoryUpstreams = getIt();

  final localPackage = await fetchPackages(configuration.useLocalPackages, () => storage.searchPackages(queryPackage));
  final hostedRepositoryUpstreamsPackage = await fetchPackages(
      configuration.useHostedUpstreamPackages, () => hostedRepositoryUpstreams.searchPackages(queryPackage));
  final gitRepositoryUpstreamsPackage =
      await fetchPackages(configuration.useGitPackages, () => gitRepositoryUpstreams.searchPackages(queryPackage));

  //combine but remove duplicates based on the version field
  final List<DartPackage> combined = {
    ...{for (var package in gitRepositoryUpstreamsPackage) package.version: package},
    ...{for (var package in hostedRepositoryUpstreamsPackage) package.version: package},
    ...{for (var package in localPackage) package.version: package},
  }.values.toList();

  final versions = combined.map((e) {
    final String name = e.name;
    final String version = e.version;
    final pubspec = jsonDecode(e.pubspec);
    return FlutterPackageClientVersionResponse(
      version,
      "${flutterModule.serverConfiguration.server.baseUrl}/packages/$name/versions/$version.tar.gz",
      pubspec,
      e.runtimeType.toString(),
      e.sha256,
    );
  }).toList();

  versions.sort((a, b) => a.version.compareTo(b.version));

  if (versions.isEmpty) {
    res.statusCode = 404;
    return jsonEncode(
      {"error": "No package found"},
    );
  }

  final response = FlutterPackageClientResponse(
    name: queryPackage,
    latest: versions.lastOrNull,
    versions: versions,
  );

  return jsonEncode(response);
}
