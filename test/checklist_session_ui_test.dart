import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todonote/data/api_client.dart';
import 'package:todonote/data/auth_storage.dart';
import 'package:todonote/data/checklists_repository.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/local/model_converters.dart';
import 'package:todonote/models/run.dart';
import 'package:todonote/models/template.dart';
import 'package:todonote/models/template_item.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/screens/checklists/run_detail_screen.dart';
import 'package:todonote/sync/connectivity_sync.dart';
import 'package:todonote/utils/active_session_lock.dart';
import 'package:todonote/utils/app_navigator.dart';
import 'package:todonote/utils/checklist_session_controller.dart';
import 'package:todonote/utils/focus_session_controller.dart';
import 'package:todonote/widgets/focus_session_banner.dart';
import 'package:todonote/widgets/primary_button.dart';

const _userId = 'user-1';
final _t0 = DateTime.utc(2026, 7);
const _bannerKey = ValueKey('checklist-session-banner');
const _stopKey = ValueKey('checklist-session-banner-stop');

http.Response _offline() => http.Response(
  jsonEncode({'error': 'server_error'}),
  503,
  headers: {'content-type': 'application/json'},
);

/// Mô phỏng nút "Bắt đầu" của các màn hình thật: xin phiên rồi mở màn run.
Future<void> _startFrom(
  BuildContext context,
  String templateId,
  String name,
) async {
  final navigator = Navigator.of(context);
  final runId = await beginChecklistRun(
    context,
    templateId: templateId,
    name: name,
  );
  if (runId != null) unawaited(openRunDetail(navigator, runId));
}

Widget _app() {
  return MaterialApp(
    navigatorKey: rootNavigatorKey,
    builder: (context, child) => FocusSessionBannerHost(child: child!),
    home: Scaffold(
      body: Builder(
        builder: (context) => Column(
          children: [
            TextButton(
              key: const ValueKey('start-t1'),
              onPressed: () => _startFrom(context, 't1', 'Buổi sáng'),
              child: const Text('Bắt đầu sáng'),
            ),
            TextButton(
              key: const ValueKey('start-t2'),
              onPressed: () => _startFrom(context, 't2', 'Buổi tối'),
              child: const Text('Bắt đầu tối'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Env {
  _Env(this.tester) {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ChecklistsRepository.forTesting(
      db,
      userId: _userId,
      client: ApiClient.forTesting(MockClient((_) async => _offline())),
    );
    ChecklistsRepository.testInstance = repo;
    now = DateTime.now().toUtc();
    final controller = ChecklistSessionController.instance;
    controller.resetForTest();
    FocusSessionController.instance.resetForTest();
    ActiveSessionLock.instance.resetForTest();
    controller.clock = () => now;
  }

  final WidgetTester tester;
  late final AppDatabase db;
  late final ChecklistsRepository repo;
  late DateTime now;

  static const _secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  ChecklistSessionController get controller =>
      ChecklistSessionController.instance;

  Future<void> seed() {
    // Ghi sync_queue cần user đã đăng nhập; giả lập kho khóa của hệ điều hành.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
    return tester.runAsync(() async {
      await AuthStorage.instance.saveUserJson({'id': _userId});
      for (final spec in const [
        ('t1', 'Buổi sáng', ['Bước 1', 'Bước 2']),
        ('t2', 'Buổi tối', ['Bước A']),
      ]) {
        final (id, title, steps) = spec;
        await db.checklistsDao.upsertTemplate(
          templateToCompanion(
            Template(id: id, title: title, createdAt: _t0, updatedAt: _t0),
            _userId,
          ),
        );
        for (var i = 0; i < steps.length; i++) {
          await db.checklistsDao.upsertTemplateItem(
            templateItemToCompanion(
              TemplateItem(
                id: '$id-i$i',
                templateId: id,
                position: i + 1,
                title: steps[i],
              ),
            ),
          );
        }
      }
    });
  }

  /// Drift chạy bất đồng bộ thật: nhường event loop thật rồi mới pump.
  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // Ghi local xong sẽ hẹn sync nền sau 2s; test không muốn chạy sync thật.
      ConnectivitySync.instance.cancelPending();
    }
  }

  Future<void> pumpApp() async {
    await tester.pumpWidget(_app());
    await settle();
  }

  Future<void> tapStart(String templateId) async {
    await tester.tap(find.byKey(ValueKey('start-$templateId')));
    await settle();
  }

  /// Rời màn hình run bằng nút back (phiên vẫn chạy).
  Future<void> leaveRunScreen() async {
    rootNavigatorKey.currentState!.pop();
    await settle();
  }

  Future<List<Run>> runs() async {
    final result = await tester.runAsync(repo.listRunsLocal);
    return result!.items;
  }

  /// Đưa đồng hồ giả tới [elapsed] kể từ lúc run bắt đầu rồi cho timer chạy.
  Future<void> advanceTo(Duration elapsed) async {
    now = controller.session.value!.startedAt.add(elapsed);
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> dispose() async {
    controller.cancel();
    FocusSessionController.instance.cancel();
    ConnectivitySync.instance.cancelPending();
    ChecklistsRepository.testInstance = null;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await AuthStorage.instance.clear();
      await db.close();
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
    controller.resetForTest();
    FocusSessionController.instance.resetForTest();
  }
}

TodoWithRelations _todo(String id) => TodoWithRelations(
  todo: Todo(
    id: id,
    title: 'Todo $id',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  ),
  tags: const [],
  subtasks: const [],
  linkedNotes: const [],
);

void main() {
  group('starting a checklist', () {
    testWidgets('opens the run screen and counts from zero', (tester) async {
      final env = _Env(tester);
      await env.seed();
      await env.pumpApp();

      await env.tapStart('t1');

      expect(find.byType(RunDetailScreen), findsOneWidget);
      expect(env.controller.session.value!.title, 'Buổi sáng');
      expect(env.controller.session.value!.elapsed, Duration.zero);
      // Màn hình run đã có đồng hồ riêng nên banner không hiện chồng lên.
      expect(find.byKey(_bannerKey), findsNothing);

      await env.dispose();
    });

    testWidgets('leaving the screen keeps the clock running in a banner', (
      tester,
    ) async {
      final env = _Env(tester);
      await env.seed();
      await env.pumpApp();
      await env.tapStart('t1');

      await env.leaveRunScreen();

      expect(find.byType(RunDetailScreen), findsNothing);
      expect(find.byKey(_bannerKey), findsOneWidget);
      expect(find.text('Buổi sáng'), findsOneWidget);
      expect(find.text('Đang làm checklist · 0/2 bước'), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);

      await env.advanceTo(const Duration(minutes: 2, seconds: 5));
      expect(find.text('02:05'), findsOneWidget);

      await env.dispose();
    });

    testWidgets('the banner brings the user back to the same run', (
      tester,
    ) async {
      final env = _Env(tester);
      await env.seed();
      await env.pumpApp();
      await env.tapStart('t1');
      await env.leaveRunScreen();

      await tester.tap(find.byKey(_bannerKey));
      await env.settle();

      expect(find.byType(RunDetailScreen), findsOneWidget);
      expect(find.byKey(_bannerKey), findsNothing);
      expect((await env.runs()).length, 1);

      await env.dispose();
    });

    testWidgets('starting the same checklist again resumes the same run', (
      tester,
    ) async {
      final env = _Env(tester);
      await env.seed();
      await env.pumpApp();
      await env.tapStart('t1');
      final runId = env.controller.session.value!.runId;
      await env.leaveRunScreen();

      await env.tapStart('t1');

      expect(find.byType(RunDetailScreen), findsOneWidget);
      expect(env.controller.session.value!.runId, runId);
      expect((await env.runs()).length, 1);
      expect(find.text('Bạn đang làm việc khác'), findsNothing);

      await env.dispose();
    });

    testWidgets('progress on the banner follows the steps that were ticked', (
      tester,
    ) async {
      final env = _Env(tester);
      await env.seed();
      await env.pumpApp();
      await env.tapStart('t1');

      await tester.tap(find.text('Bước 1'));
      await env.settle();
      await env.leaveRunScreen();

      expect(find.text('Đang làm checklist · 1/2 bước'), findsOneWidget);

      await env.dispose();
    });
  });

  group('only one thing at a time', () {
    testWidgets('a second checklist is blocked with an explanation', (
      tester,
    ) async {
      final env = _Env(tester);
      await env.seed();
      await env.pumpApp();
      await env.tapStart('t1');
      await env.leaveRunScreen();

      await env.tapStart('t2');

      expect(find.text('Bạn đang làm việc khác'), findsOneWidget);
      expect(
        find.textContaining('Bạn đang làm checklist "Buổi sáng"'),
        findsOneWidget,
      );
      // Không tạo thêm run mồ côi, và phiên cũ giữ nguyên.
      expect((await env.runs()).length, 1);
      expect(env.controller.session.value!.title, 'Buổi sáng');

      await tester.tap(find.byKey(const ValueKey('active-session-ack')));
      await env.settle();
      expect(find.text('Bạn đang làm việc khác'), findsNothing);
      expect(find.byType(RunDetailScreen), findsNothing);

      await env.dispose();
    });

    testWidgets('a running todo blocks starting a checklist', (tester) async {
      final env = _Env(tester);
      await env.seed();
      await env.pumpApp();
      FocusSessionController.instance.start(
        _todo('a'),
        const Duration(minutes: 25),
      );
      await tester.pump();

      await env.tapStart('t1');

      expect(
        find.textContaining('Bạn đang tập trung vào việc "Todo a"'),
        findsOneWidget,
      );
      expect(env.controller.session.value, isNull);
      expect((await env.runs()), isEmpty);

      await env.dispose();
    });

    testWidgets('opening another run that is in progress is blocked', (
      tester,
    ) async {
      final env = _Env(tester);
      await env.seed();
      await env.pumpApp();
      // Run mồ côi của t2 (đang chạy nhưng không có phiên).
      final orphan = (await tester.runAsync(
        () => env.repo.startRun(templateId: 't2', name: 'Buổi tối'),
      ))!.run;
      await env.tapStart('t1');
      await env.leaveRunScreen();

      unawaited(
        openChecklistRun(tester.element(find.byType(Scaffold).first), orphan),
      );
      await env.settle();

      expect(find.text('Bạn đang làm việc khác'), findsOneWidget);
      expect(find.byType(RunDetailScreen), findsNothing);
      expect(env.controller.session.value!.title, 'Buổi sáng');

      await env.dispose();
    });

    testWidgets('a finished run can still be opened for reading', (
      tester,
    ) async {
      final env = _Env(tester);
      await env.seed();
      await env.pumpApp();
      final finished = (await tester.runAsync(() async {
        final started = await env.repo.startRun(templateId: 't2');
        await env.repo.abandonRun(started.run.id);
        return (await env.repo.listRunsLocal()).items.single;
      }))!;
      expect(finished.status, RunStatus.abandoned);
      await env.tapStart('t1');
      await env.leaveRunScreen();

      unawaited(
        openChecklistRun(tester.element(find.byType(Scaffold).first), finished),
      );
      await env.settle();

      expect(find.byType(RunDetailScreen), findsOneWidget);
      expect(find.text('Bạn đang làm việc khác'), findsNothing);
      // Phiên đang chạy vẫn hiện trên banner vì đây không phải run của nó.
      expect(find.byKey(_bannerKey), findsOneWidget);

      await env.dispose();
    });
  });

  group('finishing', () {
    testWidgets('completing frees the way for the next checklist', (
      tester,
    ) async {
      final env = _Env(tester);
      await env.seed();
      await env.pumpApp();
      await env.tapStart('t1');
      await tester.tap(find.text('Bước 1'));
      await env.settle();
      await tester.tap(find.text('Bước 2'));
      await env.settle();

      await tester.tap(
        find.widgetWithText(PrimaryButton, 'Hoàn tất checklist'),
      );
      await env.settle();

      expect(env.controller.session.value, isNull);
      expect(ActiveSessionLock.instance.holder, isNull);
      expect(find.byType(RunDetailScreen), findsNothing);
      expect(find.byKey(_bannerKey), findsNothing);
      expect((await env.runs()).single.status, RunStatus.completed);

      await env.tapStart('t2');
      expect(env.controller.session.value!.title, 'Buổi tối');

      await env.dispose();
    });

    testWidgets('abandoning from the run screen ends the session', (
      tester,
    ) async {
      final env = _Env(tester);
      await env.seed();
      await env.pumpApp();
      await env.tapStart('t1');

      await tester.tap(find.byTooltip('Hủy bỏ run'));
      await env.settle();
      await tester.tap(find.widgetWithText(TextButton, 'Hủy bỏ'));
      await env.settle();

      expect(env.controller.session.value, isNull);
      expect(find.byType(RunDetailScreen), findsNothing);
      expect((await env.runs()).single.status, RunStatus.abandoned);

      await env.dispose();
    });

    testWidgets('the banner stop button asks first, then abandons the run', (
      tester,
    ) async {
      final env = _Env(tester);
      await env.seed();
      await env.pumpApp();
      await env.tapStart('t1');
      await env.leaveRunScreen();

      await tester.tap(find.byKey(_stopKey));
      await env.settle();
      expect(find.text('Hủy bỏ checklist?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Không'));
      await env.settle();
      expect(env.controller.session.value, isNotNull);
      expect((await env.runs()).single.status, RunStatus.inProgress);

      await tester.tap(find.byKey(_stopKey));
      await env.settle();
      await tester.tap(find.widgetWithText(FilledButton, 'Hủy bỏ'));
      await env.settle();

      expect(env.controller.session.value, isNull);
      expect(find.byKey(_bannerKey), findsNothing);
      expect((await env.runs()).single.status, RunStatus.abandoned);

      // Đã hủy xong thì làm checklist khác được ngay.
      await env.tapStart('t2');
      expect(env.controller.session.value!.title, 'Buổi tối');

      await env.dispose();
    });

    testWidgets('a run completed elsewhere removes the banner', (tester) async {
      final env = _Env(tester);
      await env.seed();
      await env.pumpApp();
      await env.tapStart('t1');
      await env.leaveRunScreen();
      expect(find.byKey(_bannerKey), findsOneWidget);

      // Ví dụ sync pull báo run đã hoàn tất trên thiết bị khác.
      await tester.runAsync(
        () => env.repo.completeRun(env.controller.session.value!.runId),
      );
      await tester.runAsync(env.controller.refreshFromLocal);
      await tester.pump();

      expect(env.controller.session.value, isNull);
      expect(find.byKey(_bannerKey), findsNothing);

      await env.dispose();
    });
  });
}
