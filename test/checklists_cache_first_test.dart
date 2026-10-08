import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todonote/data/api_client.dart';
import 'package:todonote/data/api_exception.dart';
import 'package:todonote/data/checklists_repository.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/local/model_converters.dart';
import 'package:todonote/models/run.dart';
import 'package:todonote/models/run_item.dart';
import 'package:todonote/models/template.dart';
import 'package:todonote/models/template_item.dart';

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

Run _run(String id, {DateTime? startedAt}) =>
    Run(id: id, templateId: 't1', name: 'Run $id', startedAt: startedAt ?? _t0);

Map<String, dynamic> _runJson(String id, {String status = 'in_progress'}) => {
  'id': id,
  'template_id': 't1',
  'name': 'Run $id',
  'status': status,
  'started_at': _t0.toIso8601String(),
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _Harness {
  _Harness() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    client = ApiClient.forTesting(
      MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        return handler(request);
      }),
    );
    repo = ChecklistsRepository.forTesting(db, userId: _userId, client: client);
  }

  late final AppDatabase db;
  late final ApiClient client;
  late final ChecklistsRepository repo;
  final calls = <String>[];
  Future<http.Response> Function(http.Request) handler = (_) async =>
      throw StateError('network must not be used');

  Future<void> markPending(String entityType, String entityId) {
    return db.syncDao.enqueueSyncOp(
      userId: _userId,
      entityType: entityType,
      entityId: entityId,
      operation: 'update',
      payload: '{}',
    );
  }
}

void main() {
  late _Harness h;

  setUp(() => h = _Harness());
  tearDown(() => h.db.close());

  group('local readers', () {
    test('paint the screen from Drift without touching the network', () async {
      await h.db.checklistsDao.upsertTemplate(
        templateToCompanion(_template('t1', 'Morning'), _userId),
      );
      await h.db.checklistsDao.upsertRun(runToCompanion(_run('r1'), _userId));

      final templates = await h.repo.listTemplatesLocal();
      final runs = await h.repo.listRunsLocal();
      final detail = await h.repo.getTemplateLocal('t1');

      expect(templates.map((t) => t.title), ['Morning']);
      expect(runs.items.map((r) => r.id), ['r1']);
      expect(runs.nextCursor, isNull);
      expect(detail!.template.title, 'Morning');
      expect(await h.repo.getTemplateLocal('missing'), isNull);
      expect(await h.repo.listCategoriesLocal(), isEmpty);
      expect(h.calls, isEmpty);
    });
  });

  group('server unavailable', () {
    setUp(() async {
      await h.db.checklistsDao.upsertTemplate(
        templateToCompanion(_template('t1', 'Cached'), _userId),
      );
      await h.db.checklistsDao.upsertRun(runToCompanion(_run('r1'), _userId));
    });

    test('5xx falls back to the cache instead of throwing', () async {
      h.handler = (_) async => _json({'error': 'server_error'}, 503);

      final templates = await h.repo.listTemplates();
      final runs = await h.repo.listRuns(limit: 20);

      expect(templates.map((t) => t.title), ['Cached']);
      expect(runs.items.map((r) => r.id), ['r1']);
      expect(h.calls, isNotEmpty);
    });

    test('client errors are still reported', () async {
      h.handler = (_) async => _json({'error': 'bad_input'}, 400);

      expect(h.repo.listTemplates(), throwsA(isA<ApiException>()));
    });
  });

  group('server data vs unsynced local changes', () {
    test(
      'a pending local edit is not overwritten by the server copy',
      () async {
        await h.db.checklistsDao.upsertTemplate(
          templateToCompanion(_template('t1', 'Local title'), _userId),
        );
        await h.markPending('checklist_template', 't1');
        h.handler = (_) async => _json({
          'items': [
            _templateJson('t1', 'Server title'),
            _templateJson('t2', 'New'),
          ],
        });

        final templates = await h.repo.listTemplates();

        expect(
          templates.map((t) => t.title),
          containsAll(['Local title', 'New']),
        );
        expect(templates.map((t) => t.title), isNot(contains('Server title')));
      },
    );

    test('server rows without pending changes are cached', () async {
      await h.db.checklistsDao.upsertTemplate(
        templateToCompanion(_template('t1', 'Old'), _userId),
      );
      h.handler = (_) async => _json({
        'items': [_templateJson('t1', 'Fresh')],
      });

      await h.repo.listTemplates();

      expect((await h.repo.listTemplatesLocal()).single.title, 'Fresh');
    });

    test(
      'first page keeps a run created offline next to the server runs',
      () async {
        await h.db.checklistsDao.upsertRun(
          runToCompanion(
            _run('offline', startedAt: _t0.add(const Duration(days: 1))),
            _userId,
          ),
        );
        await h.markPending('checklist_run', 'offline');
        h.handler = (_) async => _json({
          'items': [_runJson('server')],
          'nextCursor': 'c1',
        });

        final first = await h.repo.listRuns(limit: 20);
        final second = await h.repo.listRuns(cursor: 'c1', limit: 20);

        expect(first.items.map((r) => r.id), ['offline', 'server']);
        expect(first.nextCursor, 'c1');
        expect(second.items.map((r) => r.id), ['server']);
      },
    );

    test('refreshRun keeps a run item that was toggled offline', () async {
      await h.db.checklistsDao.upsertRun(runToCompanion(_run('r1'), _userId));
      await h.db.checklistsDao.upsertRunItem(
        runItemToCompanion(
          const RunItem(
            id: 'i1',
            runId: 'r1',
            templateItemId: 'ti1',
            status: RunItemStatus.done,
            title: 'Step 1',
            position: 0,
          ),
        ),
      );
      await h.markPending('checklist_run_item', 'i1');
      h.handler = (_) async => _json({
        'run': _runJson('r1'),
        'items': [
          {
            'id': 'i1',
            'run_id': 'r1',
            'template_item_id': 'ti1',
            'status': 'pending',
            'title': 'Step 1',
            'position': 0,
          },
          {
            'id': 'i2',
            'run_id': 'r1',
            'template_item_id': 'ti2',
            'status': 'pending',
            'title': 'Step 2',
            'position': 1,
          },
        ],
      });

      final result = await h.repo.refreshRun('r1');

      final byId = {for (final item in result.items) item.id: item};
      expect(byId['i1']!.status, RunItemStatus.done);
      expect(byId['i2']!.title, 'Step 2');
    });

    test(
      'getTemplate returns the local copy while item edits are pending',
      () async {
        await h.db.checklistsDao.upsertTemplate(
          templateToCompanion(_template('t1', 'Tpl'), _userId),
        );
        await h.db.checklistsDao.upsertTemplateItem(
          templateItemToCompanion(
            const TemplateItem(
              id: 'i1',
              templateId: 't1',
              position: 0,
              title: 'Local item',
            ),
          ),
        );
        await h.markPending('checklist_template_item', 'i1');
        h.handler = (_) async => _json({
          'template': _templateJson('t1', 'Tpl'),
          'items': [
            {
              'id': 'i1',
              'template_id': 't1',
              'position': 0,
              'title': 'Server item',
            },
          ],
        });

        final result = await h.repo.getTemplate('t1');

        expect(result.items.map((i) => i.title), ['Local item']);
      },
    );
  });

  group('deleting', () {
    test('deleteRun and deleteTemplate also remove the cached copy', () async {
      await h.db.checklistsDao.upsertTemplate(
        templateToCompanion(_template('t1', 'Tpl'), _userId),
      );
      await h.db.checklistsDao.upsertRun(runToCompanion(_run('r1'), _userId));
      h.handler = (_) async => http.Response('', 204);

      await h.repo.deleteRun('r1');
      await h.repo.deleteTemplate('t1');

      expect((await h.repo.listRunsLocal()).items, isEmpty);
      expect(await h.repo.listTemplatesLocal(), isEmpty);
    });

    test('a failed server delete keeps the cached copy', () async {
      await h.db.checklistsDao.upsertRun(runToCompanion(_run('r1'), _userId));
      h.handler = (_) async => _json({'error': 'server_error'}, 500);

      await expectLater(h.repo.deleteRun('r1'), throwsA(isA<ApiException>()));

      expect((await h.repo.listRunsLocal()).items.map((r) => r.id), ['r1']);
    });
  });
}
