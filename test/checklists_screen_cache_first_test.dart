import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todonote/data/api_client.dart';
import 'package:todonote/data/checklists_repository.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/local/model_converters.dart';
import 'package:todonote/models/template.dart';
import 'package:todonote/screens/checklists/checklists_screen.dart';
import 'package:todonote/utils/checklist_local_events.dart';

const _userId = 'user-1';
final _t0 = DateTime.utc(2026, 7);

Template _template(String id, String title) =>
    Template(id: id, title: title, createdAt: _t0, updatedAt: _t0);

Map<String, dynamic> _templateJson(String id, String title) => {
  'id': id,
  'title': title,
  'created_at': _t0.toIso8601String(),
  'updated_at': _t0.toIso8601String(),
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _Env {
  _Env(this.tester) {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    ChecklistsRepository.testInstance = ChecklistsRepository.forTesting(
      db,
      userId: _userId,
      client: ApiClient.forTesting(
        MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/checklists/templates')) {
            await templatesGate.future;
            return templatesResponse();
          }
          return _json({'items': <Object>[]});
        }),
      ),
    );
  }

  final WidgetTester tester;
  late final AppDatabase db;

  /// Giữ phản hồi danh sách template cho tới khi test cho phép.
  final templatesGate = Completer<void>();
  http.Response Function() templatesResponse = () => _json({'items': []});

  Future<void> seedTemplate(String id, String title) {
    return tester.runAsync(
      () => db.checklistsDao.upsertTemplate(
        templateToCompanion(_template(id, title), _userId),
      ),
    );
  }

  Future<void> settle() async {
    // Drift chạy bất đồng bộ thật: nhường event loop thật rồi mới pump.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  Future<void> dispose() async {
    ChecklistsRepository.testInstance = null;
    await tester.runAsync(db.close);
  }
}

void main() {
  testWidgets('shows cached templates while the server is still answering', (
    tester,
  ) async {
    final env = _Env(tester);
    await env.seedTemplate('t1', 'Cached template');
    env.templatesResponse = () => _json({
      'items': [
        _templateJson('t1', 'Server renamed'),
        _templateJson('t2', 'Brand new'),
      ],
    });

    await tester.pumpWidget(const MaterialApp(home: ChecklistsScreen()));
    await env.settle();

    // Server chưa trả lời, nhưng dữ liệu đã lưu phải hiện ngay.
    expect(find.text('Cached template'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    env.templatesGate.complete();
    await env.settle();

    // Server trả về → vẽ lại ngay với dữ liệu mới.
    expect(find.text('Server renamed'), findsOneWidget);
    expect(find.text('Brand new'), findsOneWidget);
    expect(find.text('Cached template'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await env.dispose();
  });

  testWidgets('a temporary server error does not bother the user', (
    tester,
  ) async {
    final env = _Env(tester);
    await env.seedTemplate('t1', 'Cached template');
    env.templatesResponse = () => _json({'error': 'server_error'}, 503);
    env.templatesGate.complete();

    await tester.pumpWidget(const MaterialApp(home: ChecklistsScreen()));
    await env.settle();

    expect(find.text('Cached template'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await env.dispose();
  });

  testWidgets('without any cache a server error is reported', (tester) async {
    final env = _Env(tester);
    env.templatesResponse = () => _json({'error': 'bad_input'}, 400);
    env.templatesGate.complete();

    await tester.pumpWidget(const MaterialApp(home: ChecklistsScreen()));
    await env.settle();

    expect(find.byType(SnackBar), findsOneWidget);

    await env.dispose();
  });

  testWidgets('re-reads the cache when a sync pull changes the data', (
    tester,
  ) async {
    final env = _Env(tester);
    await env.seedTemplate('t1', 'First');
    env.templatesResponse = () => _json({
      'items': [_templateJson('t1', 'First')],
    });
    env.templatesGate.complete();

    await tester.pumpWidget(const MaterialApp(home: ChecklistsScreen()));
    await env.settle();
    expect(find.text('Second'), findsNothing);

    await env.seedTemplate('t2', 'Second');
    ChecklistLocalEvents.instance.notifyChanged();
    await env.settle();

    expect(find.text('Second'), findsOneWidget);

    await env.dispose();
  });
}
