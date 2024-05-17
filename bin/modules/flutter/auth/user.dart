import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

@JsonSerializable()
class UserDefinition {
  final String name;
  final String token;
  final String? regex;

  UserDefinition({
    required this.name,
    required this.token,
    required this.regex,
  });

  factory UserDefinition.fromJson(Map<String, dynamic> json) => _$UserDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$UserDefinitionToJson(this);
}

Future<bool> userCanSeePackage(List<UserDefinition> users, String token, String package) async {
  final user = users.where((element) => element.token == token).toList().firstOrNull;
  if (user == null) {
    return false;
  }

  if (user.regex != null) {
    if (!RegExp(user.regex!).hasMatch(package)) {
      return false;
    }
  }

  return true;
}
