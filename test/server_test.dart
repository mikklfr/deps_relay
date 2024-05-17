import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:test/test.dart';

void main() {
  final port = '8080';
  final hostPubDev = 'https://pub.dev';
  final host = 'http://0.0.0.0:$port/flutter';
  late Process p;

  setUp(() async {
    p = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      environment: {'PORT': port},
    );
    // Wait for server to start and print to stdout.
    await p.stdout.first;
  });

  tearDown(() => p.kill());

  test('Root', () async {
    final response = await get(Uri.parse('$host/api/packages/bloc'));
    expect(response.statusCode, 200);

    final body = jsonDecode(response.body);
    assert (body['name'] == 'bloc');
    assert ((body['versions'] as List<dynamic>).isNotEmpty);
  });
}
