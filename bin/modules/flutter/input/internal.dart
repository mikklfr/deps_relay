import 'dart:convert';

import 'package:isar/isar.dart';

import '../flutter.dart';
import '../sources/git/git.dart';
import '../sources/hosted/hosted.dart';
import '../sources/local/local.dart';
import '../sources/local/stored_package.dart';
import 'get_package.dart';

Future internalListPackages(req, res, FlutterModule flutterModule) async {
  final store = getIt<FlutterStorage>();
  final List<StoredPackage> packages = await store.fileDatabase.storedPackages.where().findAll();
  return jsonEncode({"local_packages": packages});
}

Future internalDeletePackage(req, res, FlutterModule flutterModule, String id) async {
  final store = getIt<FlutterStorage>();
  await store.fileDatabase.writeTxn(() async {
    return store.fileDatabase.storedPackages.delete(int.parse(id));
  });

  return jsonEncode({});
}

Future internalDeleteAllPackage(req, res, FlutterModule flutterModule) async {
  final store = getIt<FlutterStorage>();
  await store.fileDatabase.writeTxn(() async {
    return store.fileDatabase.storedPackages.clear();
  });

  return jsonEncode({});
}

Future internalPurge(req, res, FlutterModule flutterModule) async {
  final store = getIt<FlutterStorage>();
  final objects = (await store.fileStorage.listObjects(bucket: store.bucketName)).contents ?? [];
  final List<StoredPackage> packages = await store.fileDatabase.storedPackages.where().findAll();

  int fileCount = 0;
  for (var object in objects) {
    if (object.key == null) {
      continue;
    }
    if (packages.any((element) => element.filename == object.key)) {
      continue;
    }
    fileCount++;
    await store.fileStorage.deleteObject(bucket: store.bucketName, key: object.key!);
  }

  int dbCount = 0;
  for (var package in packages) {
    if (objects.any((element) => element.key == package.filename)) {
      continue;
    }
    dbCount++;
    await store.fileDatabase.writeTxn(() async {
      return store.fileDatabase.storedPackages.delete(package.id);
    });
  }

  return jsonEncode({"dbCount": dbCount, "fileCount": fileCount});
}

Future internalListGit(req, res, FlutterModule flutterModule) async {
  final GitRepositoryUpstreams gitRepositoryUpstreams = getIt();
  return jsonEncode(gitRepositoryUpstreams.packages);
}

Future internalListHosted(req, res, FlutterModule flutterModule) async {
  final HostedRepositoryUpstreams hostedRepositoryUpstreams = getIt();
  return jsonEncode(hostedRepositoryUpstreams.upstreams);
}
