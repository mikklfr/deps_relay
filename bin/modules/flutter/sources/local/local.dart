import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aws_s3_api/s3-2006-03-01.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart';
import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:tar/tar.dart';
import 'package:yaml/yaml.dart';

import '../dart_package.dart';
import 'stored_package.dart';

part 'local.g.dart';

@JsonSerializable()
class Package {
  final String name;
  final String version;
  final String pubspec;
  @JsonKey(name: 'archive_url')
  final String archiveUrl;

  Package({required this.name, required this.version, this.pubspec = "", this.archiveUrl = ""});

  factory Package.fromJson(Map<String, dynamic> json) => _$PackageFromJson(json);

  Map<String, dynamic> toJson() => _$PackageToJson(this);
}

class LocalDartPackage extends DartPackage {
  @override
  final String name;
  @override
  final String version;
  @override
  final String pubspec;
  @override
  final String? sha256;

  final String filename;

  LocalDartPackage(
      {required this.name, required this.version, required this.pubspec, required this.filename, required this.sha256});
}

class FlutterStorage {
  final S3 fileStorage;
  final Isar fileDatabase;
  final String bucketName;

  Future<Iterable<Package>> listPackages() async {
    final packages = await fileDatabase.storedPackages.buildQuery().findAll();
    return packages
        .map((e) => {
              "name": e.package,
              "version": e.version,
              "pubspec": e.pubspec,
            })
        .map((e) => Package.fromJson(e))
        .toList();
  }

  Future<List<LocalDartPackage>> searchPackages(String package) async {
    final packages = await fileDatabase.storedPackages.filter().packageEqualTo(package).findAll();
    return packages
        .map((e) => LocalDartPackage(
              name: e.package,
              version: e.version,
              pubspec: e.pubspec,
              filename: e.filename,
              sha256: e.sha256,
            ))
        .toList();
  }

  Future<LocalDartPackage?> getPackage(String package, String version) async {
    final dbPkg =
        await fileDatabase.storedPackages.filter().packageEqualTo(package).and().versionEqualTo(version).findFirst();

    if (dbPkg != null) {
      return LocalDartPackage(
        name: dbPkg.package,
        version: dbPkg.version,
        pubspec: dbPkg.pubspec,
        filename: dbPkg.filename,
        sha256: dbPkg.sha256,
      );
    } else {
      return null;
    }
  }

  static Future<FlutterStorage> init({
    required String bucketName,
    required String databasePath,
    String? databaseName,
    required String s3Region,
    required String s3Endpoint,
    required String s3AccessKey,
    required String s3SecretKey,
  }) async {
    final dir = Directory(databasePath);
    if (!await dir.exists()) {
      await dir.create();
    }

    await Isar.initializeIsarCore(download: true);
    final isar = await Isar.open(
      [StoredPackageSchema],
      directory: dir.path,
      name: databaseName ?? Isar.defaultName,
    );

    final s3 = S3(
      region: s3Region,
      endpointUrl: s3Endpoint,
      credentials: AwsClientCredentials(accessKey: s3AccessKey, secretKey: s3SecretKey),
    );
    try {
      await s3.headBucket(bucket: bucketName);
    } catch (e) {
      await s3.createBucket(bucket: bucketName);
    }
    return FlutterStorage(s3, isar, bucketName);
  }

  FlutterStorage(this.fileStorage, this.fileDatabase, this.bucketName);

  Future<String> readPubspec(Uint8List tarball) async {
    final completer = Completer<String>();
    final tarReader = TarReader(Stream.value(tarball.toList()).transform(gzip.decoder));
    while (await tarReader.moveNext()) {
      final entry = tarReader.current;
      final fileName = entry.header.name;
      if (fileName == '/pubspec.yaml' || fileName == 'pubspec.yaml') {
        final file = Uint8List.fromList(await entry.contents.first);
        final fileContent = utf8.decode(file);
        final pubspec = loadYaml(fileContent);
        completer.complete(jsonEncode(pubspec));
        break;
      } else {
        continue;
      }
    }
    return completer.future;
  }

  Future<Uint8List> storeTarball(package, version, Uint8List tarball) async {
    // required if using upstream aws_client that does not support names with :
    // final name = uuid.v4().replaceAll("-", "");
    final name = "$package-$version";
    String pubspec = await readPubspec(tarball);
    await fileStorage.putObject(
      bucket: bucketName,
      key: '$name.tar.gz',
      metadata: {
        'package': package,
        'version': version,
      },
      body: tarball,
    );
    await fileDatabase.writeTxn(() async {
      return await fileDatabase.storedPackages.put(StoredPackage(
        package,
        version,
        '$name.tar.gz',
        pubspec,
        sha256.convert(tarball).toString(),
      ));
    });
    return tarball;
  }

  Future<LocalDartPackage> store(package, version, String remoteVersion) async {
    final tarball = (await get(Uri.parse(remoteVersion))).bodyBytes;
    await storeTarball(package, version, tarball);
    return (await getPackage(package, version))!;
  }

  Future<Uint8List> getTarball(LocalDartPackage storedPackage) async {
    final file = (await fileStorage.getObject(bucket: bucketName, key: storedPackage.filename));
    return file.body ?? Uint8List(0);
  }

  Future<bool> closeDatabase() async {
    try {
      return await fileDatabase.close();
    } catch (e) {
      return false;
    }
  }
}
