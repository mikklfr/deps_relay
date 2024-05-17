import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alfred/alfred.dart';
import 'package:async/async.dart';
import 'package:aws_s3_api/s3-2006-03-01.dart';
import 'package:crypto/crypto.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart';
import 'package:isar/isar.dart';
import 'package:tar/tar.dart';
import 'package:test/scaffolding.dart';
import 'package:tmp_path/tmp_path.dart';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

import '../../../bin/configuration/configuration.dart';
import '../../../bin/modules/flutter/flutter.dart';
import '../../../bin/modules/flutter/sources/local/local.dart';

class RunServer {
  CancelableOperation job;
  FlutterStorage storage;
  String baseUrl;
  int port;

  RunServer(this.job, this.storage, this.baseUrl, this.port);
}

extension PortBaseUrl on int {
  String get baseUrl => "http://127.0.0.1:$this/flutter";
}

Future<Configuration> _configuration() async =>  Configuration.fromFile("conf/configuration.json");

void main() {
  final List<CancelableOperation> jobs = [];

  Future<RunServer> runServer(Configuration configuration) async {
    final app = Alfred();
    await FlutterModule.create(alfred: app, configuration: configuration);
    final CancelableOperation job = CancelableOperation.fromFuture(app.listen(configuration.server.port));
    await Future.delayed(Duration(milliseconds: 1));
    return RunServer(
      job,
      GetIt.instance(),
      configuration.server.baseUrl,
      configuration.server.port,
    );
  }

  Future<RunServer> runTestServer({
    required String dbPath,
    required String bucketName,
    required bool useLocalPackages,
    required bool useHostedUpstreamPackages,
    required bool useGitPackages,
    required bool storePackages,
    String? dbName,
  }) async {
    final port = await getUnusedPort();
    var configuration = await _configuration();
    configuration = configuration.copyWith(
      server: ServerConfiguration(baseUrl: port.baseUrl, port: port),
      flutter: configuration.flutter.copyWith(
        requiresAuthentication: false,
        useLocalPackages: useLocalPackages,
        useHostedUpstreamPackages: useHostedUpstreamPackages,
        useGitPackages: useGitPackages,
        storePackages: storePackages,
        database: FlutterModuleDatabaseConfiguration(
          path: dbPath,
          name: dbName ?? Uuid().v4(),
        ),
        storage: configuration.flutter.storage.copyWith(s3Bucket: bucketName),
      ),
    );

    return await runServer(configuration);
  }

  Future<void> clearBucket(String bucketName, {bool recreate = true}) async {
    final storage = (await _configuration()).flutter.storage;
    final s3 = S3(
      region: storage.s3Region,
      endpointUrl: storage.s3Endpoint,
      credentials: AwsClientCredentials(
        accessKey: storage.s3AccessKey,
        secretKey: storage.s3SecretKey,
      ),
    );

    try {
      await s3.headBucket(bucket: bucketName);
    } catch (e) {
      if (recreate == false) {
        return;
      } else {
        await s3.createBucket(bucket: bucketName);
        return;
      }
    }

    final files = (await s3.listObjects(bucket: bucketName)).contents ?? [];
    for (final file in files) {
      if (file.key == null) {
        continue;
      }
      await s3.deleteObject(bucket: bucketName, key: file.key!);
    }

    try {
      await s3.deleteBucket(bucket: bucketName);
    } catch (e) {
      print(e);
    }
    if (recreate) {
      await s3.createBucket(bucket: bucketName);
    }
  }

  setUp(() async => await GetIt.I.reset());

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  tearDown(() async {
    for (final job in jobs) {
      job.cancel();
    }
    await clearBucket('nothing', recreate: false);
    await clearBucket('test-local', recreate: false);
    await clearBucket('test-local2', recreate: false);
    await clearBucket('test-git-cache', recreate: false);
    await clearBucket('test-git-cache2', recreate: false);
  });

  test('[Flutter][ListPackages] PubDev Upstream package', () async {
    final server = await runTestServer(
      dbPath: tmpPath(),
      bucketName: 'nothing',
      useLocalPackages: false,
      useHostedUpstreamPackages: true,
      useGitPackages: false,
      storePackages: false,
    );

    final r = await get(Uri.parse("${server.baseUrl}/api/packages/yaml"));
    final answer = jsonDecode(r.body);
    final r2 = await get(Uri.parse("https://pub.dev/api/packages/yaml"));
    final answer2 = jsonDecode(r2.body);

    assert(answer['name'] == answer2['name']);
    assert(answer['versions'].length == answer2['versions'].length);
  });

  test('[Flutter][ListPackages] Local package', () async {
    final tmpSharedDb = tmpPath();
    final sharedDbName = Uuid().v4();

    await clearBucket('test-local');

    final server = await runTestServer(
      dbPath: tmpSharedDb,
      bucketName: 'test-local',
      useLocalPackages: true,
      useHostedUpstreamPackages: true,
      useGitPackages: false,
      storePackages: true,
      dbName: sharedDbName,
    );

    await get(Uri.parse("${server.baseUrl}/packages/bloc/versions/1.0.0.tar.gz"));
    await server.job.cancel();
    await server.storage.closeDatabase();
    await GetIt.I.reset();

    final server2 = await runTestServer(
      dbPath: tmpSharedDb,
      bucketName: 'test-local',
      useLocalPackages: true,
      useHostedUpstreamPackages: false,
      useGitPackages: false,
      storePackages: false,
      dbName: sharedDbName,
    );

    final r = await get(Uri.parse("${server2.baseUrl}/api/packages/bloc"));
    final answer = jsonDecode(r.body);
    assert((answer['versions'] as List).isNotEmpty);
    assert(((answer['versions'] as List).first)['version'] == "1.0.0");
    assert(answer['name'] == 'bloc');
  });

  test('[Flutter][ListPackages] Git Upstream package', () async {
    final server = await runTestServer(
      dbPath: tmpPath(),
      bucketName: 'nothing',
      useLocalPackages: false,
      useHostedUpstreamPackages: false,
      useGitPackages: true,
      storePackages: false,
    );

    final r = await get(Uri.parse("${server.baseUrl}/api/packages/provider"));
    final answer = jsonDecode(r.body);
    assert((answer['versions'] as List).isNotEmpty);
    assert(answer['name'] == 'provider');
  });

  test('[Flutter][GetPackage] Local package', () async {
    final tmpSharedDb = tmpPath();
    final sharedDbName = Uuid().v4();
    await clearBucket('test-local2');

    final server = await runTestServer(
      dbPath: tmpSharedDb,
      bucketName: 'test-local2',
      useLocalPackages: false,
      useHostedUpstreamPackages: true,
      useGitPackages: false,
      storePackages: true,
      dbName: sharedDbName,
    );

    await get(Uri.parse("${server.baseUrl}/packages/bloc/versions/1.0.0.tar.gz"));
    await server.job.cancel();
    await server.storage.closeDatabase();
    await GetIt.I.reset();

    final server2 = await runTestServer(
      dbPath: tmpSharedDb,
      bucketName: 'test-local2',
      useLocalPackages: true,
      useHostedUpstreamPackages: false,
      useGitPackages: false,
      storePackages: false,
      dbName: sharedDbName,
    );

    final r = await get(Uri.parse("${server2.baseUrl}/packages/bloc/versions/1.0.0.tar.gz"));
    final body = r.bodyBytes;

    final tarReader = TarReader(Stream.value(body.toList()).transform(gzip.decoder));
    while (await tarReader.moveNext()) {
      final entry = tarReader.current;
      final fileName = entry.header.name;
      if (fileName != '/pubspec.yaml') {
        continue;
      }
      final file = Uint8List.fromList(await entry.contents.first);
      final fileContent = utf8.decode(file);
      final pubspec = loadYaml(fileContent);
      assert(pubspec['name'] == 'payment_provision');
    }
  });

  test('[Flutter][GetPackage] PubDev Upstream package', () async {
    final server = await runTestServer(
      dbPath: tmpPath(),
      bucketName: 'nothing',
      useLocalPackages: false,
      useHostedUpstreamPackages: true,
      useGitPackages: false,
      storePackages: false,
    );

    final r = await get(Uri.parse("${server.baseUrl}/packages/bloc/versions/8.1.4.tar.gz"));
    var digest = sha256.convert(r.bodyBytes).toString();

    final r2 = await get(Uri.parse("https://pub.dev/packages/bloc/versions/8.1.4.tar.gz"));
    var digest2 = sha256.convert(r2.bodyBytes).toString();

    assert(digest == digest2);
  });

  Future<CancelableOperation> gitPackage(String dbPath, String bucketName, bool storePackage) async {
    final port = await getUnusedPort();

    var configuration = await _configuration();
    configuration = configuration.copyWith(
      server: ServerConfiguration(baseUrl: port.baseUrl, port: port),
      flutter: configuration.flutter.copyWith(
        requiresAuthentication: false,
        useLocalPackages: false,
        useHostedUpstreamPackages: false,
        useGitPackages: true,
        storePackages: storePackage,
        database: FlutterModuleDatabaseConfiguration(
          path: dbPath,
          name: Uuid().v4(),
        ),
        storage: configuration.flutter.storage.copyWith(s3Bucket: bucketName),
      ),
    );

    final job = await runServer(configuration);
    final r = await get(Uri.parse("${configuration.server.baseUrl}/packages/provider/versions/6.1.2.tar.gz"));
    final body = r.bodyBytes;

    final tarReader = TarReader(Stream.value(body.toList()).transform(gzip.decoder));
    while (await tarReader.moveNext()) {
      final entry = tarReader.current;
      final fileName = entry.header.name;
      if (fileName != '/pubspec.yaml') {
        continue;
      }
      final file = Uint8List.fromList(await entry.contents.first);
      final fileContent = utf8.decode(file);
      final pubspec = loadYaml(fileContent);
      assert(pubspec['name'] == 'provider');
    }
    return job.job;
  }

  test('[Flutter][GetPackage] Git package without cache', () async {
    await clearBucket('test-git-cache');
    return gitPackage(tmpPath(), 'test-git-cache', false);
  });

  test('[Flutter][GetPackage] Git package should be cached', () async {
    await clearBucket('test-git-cache2');

    final dbPath = tmpPath();
    await gitPackage(dbPath, 'test-git-cache2', true);

    await GetIt.I.reset();

    final server = await runTestServer(
        dbPath: dbPath,
        bucketName: 'test-git-cache2',
        useLocalPackages: true,
        useHostedUpstreamPackages: false,
        useGitPackages: false,
        storePackages: false);

    final start = DateTime.now();
    await get(Uri.parse("${server.baseUrl}/packages/provider/versions/6.1.2.tar.gz"));
    final end = DateTime.now();
    final duration = end.difference(start).inSeconds;
    assert(duration < 1);
  });

  test('[Flutter][GetPackage] Local only should not use git config', () async {
    final server = await runTestServer(
      dbPath: tmpPath(),
      bucketName: 'nothing',
      useLocalPackages: true,
      useHostedUpstreamPackages: false,
      useGitPackages: false,
      storePackages: false,
    );

    final r = await get(Uri.parse("${server.baseUrl}/packages/provider/versions/6.1.2.tar.gz"));
    assert(r.statusCode == 404);
  });

  test('[Flutter][GetPackage] Local only should not use pub.dev upstream', () async {
    final server = await runTestServer(
      dbPath: tmpPath(),
      bucketName: 'nothing',
      useLocalPackages: true,
      useHostedUpstreamPackages: false,
      useGitPackages: false,
      storePackages: false,
    );

    final r = await get(Uri.parse("${server.baseUrl}/packages/provider/versions/6.1.2.tar.gz"));
    assert(r.statusCode == 404);
  });

  final compatibleVersionMatcher = RegExp(r"\d+\.\d+\.\d+(\+\d+)?(-[a-zA-Z]+(\.\d+)?)?");
  test('test versions regex', () {
    final input = "erplus/1.1.5_android_result";
    assert(compatibleVersionMatcher.hasMatch(input));
    assert(compatibleVersionMatcher.firstMatch(input)!.group(0).toString() == "1.1.5");

    final input2 = "1.1.5";
    assert(compatibleVersionMatcher.hasMatch(input2));
    assert(compatibleVersionMatcher.firstMatch(input2)!.group(0).toString() == "1.1.5");

    final input3 = "v1.1.5";
    assert(compatibleVersionMatcher.hasMatch(input3));
    assert(compatibleVersionMatcher.firstMatch(input3)!.group(0).toString() == "1.1.5");

    final input4 = "v1.1.5-rc.1";
    assert(compatibleVersionMatcher.hasMatch(input4));
    assert(compatibleVersionMatcher.firstMatch(input4)!.group(0).toString() == "1.1.5-rc.1");

    final input5 = "v1.1.5+2";
    assert(compatibleVersionMatcher.hasMatch(input5));
    assert(compatibleVersionMatcher.firstMatch(input5)!.group(0).toString() == "1.1.5+2");

    final input6 = "42";
    assert(!compatibleVersionMatcher.hasMatch(input6));

    final input7 = "abc";
    assert(!compatibleVersionMatcher.hasMatch(input7));

    final input8 = "1.1.5-ok";
    assert(compatibleVersionMatcher.hasMatch(input8));
    assert(compatibleVersionMatcher.firstMatch(input8)!.group(0).toString() == "1.1.5-ok");
  });
}

Future<int> getUnusedPort() {
  return ServerSocket.bind(InternetAddress.anyIPv4, 0).then((socket) {
    var port = socket.port;
    socket.close();
    return port;
  });
}
