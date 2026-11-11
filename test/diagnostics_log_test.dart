import 'dart:io';

import 'package:ayra/services/diagnostics_log.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ayra-diag-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );
    await DiagnosticsLog.clear();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await tempDir.delete(recursive: true);
  });

  test('append then readTail returns the lines', () async {
    await DiagnosticsLog.append('[listening] Listening…');
    await DiagnosticsLog.append('[heard] Last heard: "hello ayra"');
    final tail = await DiagnosticsLog.readTail();
    expect(tail, contains('[listening] Listening…'));
    expect(tail, contains('[heard] Last heard: "hello ayra"'));
  });

  test('readTail is empty when there is no log yet', () async {
    expect(await DiagnosticsLog.readTail(), isEmpty);
  });

  test('log rotates: the file stays bounded', () async {
    for (var i = 0; i < 310; i++) {
      await DiagnosticsLog.append('line $i');
    }
    final tail = await DiagnosticsLog.readTail(maxLines: 500);
    final lines = tail.split('\n');
    // Trimming keeps the last 200 lines once the file passes 300,
    // so it can briefly hold up to 301 — never grows without bound.
    expect(lines.length, lessThanOrEqualTo(301));
    expect(tail, contains('line 309'));
    expect(tail, isNot(contains('line 0\n')));
  });

  test('clear deletes the log', () async {
    await DiagnosticsLog.append('something');
    expect(await DiagnosticsLog.readTail(), isNotEmpty);
    await DiagnosticsLog.clear();
    expect(await DiagnosticsLog.readTail(), isEmpty);
  });
}
