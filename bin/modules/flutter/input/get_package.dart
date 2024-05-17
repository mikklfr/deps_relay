import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:http/http.dart';

import '../flutter.dart';
import '../sources/git/git.dart';
import '../sources/hosted/hosted.dart';
import '../sources/local/local.dart';

final getIt = GetIt.instance;

Future getPackage(String package, String version, HttpResponse res, FlutterModule flutterModule) async {
  final FlutterModuleConfiguration configuration = getIt();
  final FlutterStorage storage = getIt();
  final HostedRepositoryUpstreams hostedRepositoryUpstreams = getIt();
  final GitRepositoryUpstreams gitRepositoryUpstreams = getIt();

  if (configuration.useLocalPackages) {
    final localPackage = await storage.getPackage(package, version);
    if (localPackage != null) {
      return await storage.getTarball(localPackage);
    }
  }

  if (configuration.useHostedUpstreamPackages) {
    final hostedDartPackage = await hostedRepositoryUpstreams.getPackage(package, version);
    if (hostedDartPackage != null) {
      if (configuration.storePackages && (await storage.getPackage(package, version)) == null) {
        final addedPackage = await storage.store(package, version, hostedDartPackage.archiveUrl);
        return storage.getTarball(addedPackage);
      } else {
        return (await get(Uri.parse(hostedDartPackage.archiveUrl))).bodyBytes;
      }
    }
  }

  if (configuration.useGitPackages) {
    final gitRepositoryUpstreamsPackage = await gitRepositoryUpstreams.getPackage(package, version);
    if (gitRepositoryUpstreamsPackage != null) {
      final data = await gitRepositoryUpstreams.generateTarball(gitRepositoryUpstreamsPackage);
      if (configuration.storePackages && (await storage.getPackage(package, version)) == null) {
        storage.storeTarball(package, version, data);
      }
      return data;
    }
  }

  res.statusCode = 404;
  return jsonEncode({"error": "Package not found"});
}
