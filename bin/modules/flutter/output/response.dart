import 'package:json_annotation/json_annotation.dart';

part 'response.g.dart';

@JsonSerializable()
class FlutterPackageClientVersionResponse {
  @JsonKey(name: 'archive_sha256', includeIfNull: false)
  final String? archiveSha256;
  final String version;
  @JsonKey(name: 'archive_url')
  final String archiveUrl;
  final Map<String, dynamic>? pubspec;
  @JsonKey(name: '_source')
  final String source;

  FlutterPackageClientVersionResponse(
    this.version,
    this.archiveUrl,
    this.pubspec,
    this.source,
    this.archiveSha256,
  );

  factory FlutterPackageClientVersionResponse.fromJson(Map<String, dynamic> json) =>
      _$FlutterPackageClientVersionResponseFromJson(json);

  Map<String, dynamic> toJson() => _$FlutterPackageClientVersionResponseToJson(this);
}

@JsonSerializable()
class FlutterPackageClientResponse {
  final String name;
  final FlutterPackageClientVersionResponse? latest;
  final List<FlutterPackageClientVersionResponse> versions;

  factory FlutterPackageClientResponse.fromJson(Map<String, dynamic> json) =>
      _$FlutterPackageClientResponseFromJson(json);

  Map<String, dynamic> toJson() => _$FlutterPackageClientResponseToJson(this);

  FlutterPackageClientResponse({required this.name, required this.latest, required this.versions});
}
