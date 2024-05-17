import 'dart:convert';

import 'package:http/http.dart';
import 'package:json_annotation/json_annotation.dart';

import '../dart_package.dart';

part 'hosted.g.dart';

class HostedRepositoryUpstreams {
  List<HostedRepositoryUpstream> upstreams;

  HostedRepositoryUpstreams(this.upstreams);

  Future<HostedRepositoryDartPackage?> getPackage(String package, String version) async =>
      (await searchPackages(package)).where((element) => element.version == version).firstOrNull;

  Future<List<HostedRepositoryDartPackage>> searchPackages(String package) async {
    final List<HostedRepositoryDartPackage> packages = [];
    for (var upstream in upstreams) {
      final upstreamPackages = await upstream.searchPackages(package);
      packages.addAll(upstreamPackages);
    }
    return packages;
  }
}

@JsonSerializable()
class HostedRepositoryUpstream {
  final String url;

  HostedRepositoryUpstream(this.url);

  factory HostedRepositoryUpstream.fromJson(Map<String, dynamic> json) => _$HostedRepositoryUpstreamFromJson(json);

  Map<String, dynamic> toJson() => _$HostedRepositoryUpstreamToJson(this);

  Future<Iterable<HostedRepositoryDartPackage>> searchPackages(String queryPackage) async {
    try {
      final List<dynamic> upstreams =
          jsonDecode((await get(Uri.parse('$url/api/packages/$queryPackage'))).body)['versions'];

      return upstreams
          .map((package) => HostedRepositoryDartPackage(
                name: queryPackage,
                version: package['version'],
                pubspec: jsonEncode(package['pubspec']),
                archiveUrl: package['archive_url'],
                sha256: package['archive_sha256'],
              ))
          .toList();
    } catch (e) {
      return [];
    }
  }
}

class HostedRepositoryDartPackage extends DartPackage {
  @override
  final String name;
  @override
  final String version;
  @override
  final String pubspec;
  final String archiveUrl;
  @override
  final String? sha256;

  HostedRepositoryDartPackage({
    required this.name,
    required this.version,
    required this.pubspec,
    required this.archiveUrl,
    required this.sha256,
  });
}
