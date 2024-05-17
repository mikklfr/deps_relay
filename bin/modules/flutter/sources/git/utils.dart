import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git/git.dart';
import 'package:git_clone/git_clone.dart';
import 'package:rw_git/rw_git.dart';
import 'package:tar/tar.dart';
import 'package:tmp_path/tmp_path.dart';
import 'package:yaml/yaml.dart';

import 'git.dart';

String removeOrigin(String version) => version.replaceAll("origin/", "");

final _compatibleVersionMatcher = RegExp(r"\d+\.\d+\.\d+(\+\d+)?(-[a-zA-Z]+(\.\d+)?)?");

String matchWithCompatibleVersion(String version) {
  if (_compatibleVersionMatcher.hasMatch(version)) {
    return _compatibleVersionMatcher.firstMatch(version)![0]!;
  } else {
    return "";
  }
}

Future<void> addKnownHost(String host) async {
  final command = "ssh-keyscan $host >> ~/.ssh/known_hosts";
  await Process.run("sh", ["-c", command]);
  await Process.run("sh", ["-c", "awk -i inplace '!seen[\$0]++' ~/.ssh/known_hosts"]);
}

Future<Uint8List> tarDirectory(String tmp, String finalPath, String? subPath) async {
  final entries = await Directory(finalPath).list(recursive: true).where((event) => event is File).toList();
  final StreamController<TarEntry> tarEntries = StreamController<TarEntry>();
  for (var entry in entries) {
    if (entry.path.contains(".git")) {
      continue;
    }
    var fileName = entry.path.replaceAll(tmp, "");
    if (fileName.startsWith("/")) {
      fileName = fileName.substring(1);
    }
    if (subPath != null) {
      fileName = fileName.substring(subPath.length + 1);
    }
    final tarEntry = TarEntry.data(
      TarHeader(
        name: fileName,
        mode: int.parse('644', radix: 8),
      ),
      await File(entry.path).readAsBytes(),
    );
    tarEntries.add(tarEntry);
  }
  tarEntries.close();
  final feed = await tarEntries.stream.transform(tarWriter).transform(gzip.encoder).toList();
  final content = Uint8List.fromList(feed.expand((element) => element).toList());
  return content;
}

Future<List<VersionPubspecPair>> readRepository(GitRepositoryDartPackageDefinition packageDefinition) async {
  final tmp = await cloneRepo(
    packageDefinition.url,
    null,
    packageDefinition.sshHost,
  );

  RwGit rwGit = RwGit();
  final List<VersionPubspecPair> result = [];
  final branches = await rwGit.fetchBranches(tmp);
  final tags = await rwGit.fetchTags(tmp);

  final branchesAndTags = [...branches, ...tags];

  for (var item in branchesAndTags) {
    final branchToCheckout = item;
    await rwGit.checkout(tmp, branchToCheckout);
    String pubSpecPath;
    if (packageDefinition.subPath != null) {
      pubSpecPath = "$tmp/${packageDefinition.subPath}/pubspec.yaml";
    } else {
      pubSpecPath = "$tmp/pubspec.yaml";
    }
    final pubspecFile = File(pubSpecPath);
    try {
      final content = pubspecFile.readAsBytes().asStream();
      final yaml = await utf8.decodeStream(content);
      String json = jsonEncode(loadYaml(yaml));

      String rewriteVersion = branchToCheckout;
      rewriteVersion = removeOrigin(rewriteVersion);
      rewriteVersion = matchWithCompatibleVersion(rewriteVersion);

      final Map<String, dynamic> newMap = jsonDecode(json);
      newMap['version'] = rewriteVersion;
      newMap['name'] = packageDefinition.name;
      newMap.remove('flutter');
      newMap.remove('homepage');

      json = jsonEncode(newMap);

      result.add(VersionPubspecPair(branchToCheckout, json, packageDefinition.sshHost));
    } catch (e) {
      continue;
    }
  }
  try {
    await Directory(tmp).delete(recursive: true);
  } catch (e) {
    // ignore
  }
  return result;
}

Future<String> cloneRepo(String url, String? branch, String? sshHost) async {
  if (sshHost != null) {
    addKnownHost(sshHost);
  }

  final tmp = tmpPath();
  final completer = Completer<String>();
  final Map<String, dynamic> options = {};
  if (branch != null) {
    options["--branch"] = branch;
  }

  gitClone(
      repo: url,
      directory: tmp,
      options: options,
      callback: (r) async {
        if (r.exitCode != 0) {
          completer.completeError("Failed to clone repository");
          return;
        }
        completer.complete(tmp);
      });
  return completer.future;
}

extension GitBranches on RwGit {
  Future<List<String>> fetchBranches(String directory) async {
    final processResult = await runGit(
      ['branch', '-r'],
      throwOnError: false,
      echoOutput: false,
      processWorkingDir: directory,
    );
    return processResult.stdout.toString().split("\n").map((e) => e.trim()).toList();
  }
}
