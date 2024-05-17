import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';

part 'stored_package.g.dart';

@collection
@JsonSerializable()
class StoredPackage {
  Id id = Isar.autoIncrement;

  String package;
  String version;
  String filename;
  String pubspec;
  String sha256;

  StoredPackage(this.package, this.version, this.filename, this.pubspec, this.sha256);

  factory StoredPackage.fromJson(Map<String, dynamic> json) => _$StoredPackageFromJson(json);
  Map<String, dynamic> toJson() => _$StoredPackageToJson(this);
}