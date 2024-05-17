import 'dart:convert';

import 'package:alfred/alfred.dart';
import 'package:ttl_cache/ttl_cache.dart';

import '../auth/user.dart';
import '../flutter.dart';
import 'get_package.dart';
import 'internal.dart';
import 'search_packages.dart';

class FlutterHttpRouting {
  final Alfred alfred;
  final FlutterModule flutterModule;

  FlutterHttpRouting(this.alfred, this.flutterModule);

  final cache = TtlCache<String, dynamic>(
    defaultTtl: const Duration(hours: 1),
  );

  flutterHttpAuthMiddleWare(HttpRequest request, HttpResponse response) async {
    if (!flutterModule.configuration.requiresAuthentication) {
      return null;
    }

    if (!await userCanSeePackage(flutterModule.configuration.users, request.bearerToken, request.package)) {
      response.statusCode = 401;
      return jsonEncode({"error": "no tokens"});
    }
    return null;
  }

  Future<void> init() async {
    alfred.get('/flutter/packages/:package/versions/*', middleware: [flutterHttpAuthMiddleWare], (req, res) async {
      final r = req.uri.toString();
      final package = req.params['package'];
      var version = r.replaceAll("/flutter/packages/$package/versions/", "");
      version = version.split(".tar.gz")[0];
      return getPackage(package, version, res, flutterModule);
    });
    alfred.get('/flutter/api/packages/:package', middleware: [flutterHttpAuthMiddleWare], (req, res) async {
      final cached = cache.get(req.uri.toString());
      if (cached != null) {
        return cached;
      }

      final answer = await searchPackages(req.params['package'], res, flutterModule);
      cache.set(req.uri.toString(), answer);
      return answer;
    });

    if (flutterModule.configuration.enableDebugRoutes) {
      alfred.get('/flutter/_/local', (req, res) async {
        final answer = await internalListPackages(req, res, flutterModule);
        return answer;
      });

      alfred.delete(
        '/flutter/_/local/:id',
        (req, res) async => internalDeletePackage(req, res, flutterModule, req.params['id']),
      );

      alfred.delete(
        '/flutter/_/local',
        (req, res) async => internalDeleteAllPackage(req, res, flutterModule),
      );

      alfred.get(
        '/flutter/_/local/purge',
        (req, res) async => internalPurge(req, res, flutterModule),
      );

      alfred.get(
        '/flutter/_/git',
        (req, res) async => internalListGit(req, res, flutterModule),
      );

      alfred.get(
        '/flutter/_/hosted',
        (req, res) async => internalListHosted(req, res, flutterModule),
      );
    }
  }
}

extension HttpRequestParser on HttpRequest {
  String get bearerToken => headers['authorization']?.firstOrNull?.split("Bearer ").lastOrNull ?? '';

  String get package => params['package'] ?? '';
}
