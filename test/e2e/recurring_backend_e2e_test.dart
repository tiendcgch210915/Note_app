// Tích hợp thật: mã Mobile (TodosRepository + SyncWorker, DB Drift trong bộ nhớ)
// nói chuyện với backend thật qua HTTP. Chỉ chạy khi có địa chỉ server:
//
//   (backend) TURSO_DATABASE_URL=file:<đường dẫn tạm> npx tsx src/server.ts
//   flutter test test/e2e/recurring_backend_e2e_test.dart \
//     --dart-define=TODO_NOTE_E2E_BASE_URL=http://127.0.0.1:3100/api/v1
//
// LUÔN trỏ backend vào một DB cô lập (SQLite `file:`), không dùng DB thật: test
// này tự đăng ký một user thử và tạo/xóa todo.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/remote/api_client_dio.dart';
import 'package:todonote/data/todos_repository.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/sync/connectivity_sync.dart';
import 'package:todonote/sync/sync_worker.dart';
import 'package:todonote/utils/json_utils.dart';

const _baseUrl = String.fromEnvironment('TODO_NOTE_E2E_BASE_URL');

void main() {
  final skip = _baseUrl.isEmpty
      ? 'Đặt --dart-define=TODO_NOTE_E2E_BASE_URL=<.../api/v1> và chạy backend '
            'trên DB cô lập để chạy bài test này.'
      : null;

  late String token;
  late String userId;

  // Backend đóng sổ các ngày đã qua theo múi giờ của user (Asia/Ho_Chi_Minh):
  // mọi ngày dùng trong test là hôm nay hoặc tương lai theo giờ đó.
  final vn = DateTime.now().toUtc().add(const Duration(hours: 7));
  final today = DateTime(vn.year, vn.month, vn.day);
  DateTime plus(int days) => today.add(Duration(days: days));

  Map<String, String> authHeaders() => {
    'authorization': 'Bearer $token',
    'content-type': 'application/json',
  };

  setUpAll(() async {
    if (skip != null) return;
    HttpOverrides.global = null; // flutter_test chặn HTTP thật theo mặc định.
    final email =
        'e2e-${DateTime.now().microsecondsSinceEpoch}@example.test'; // user thử
    final password = 'E2e-${DateTime.now().microsecondsSinceEpoch}-Pw!';
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/register'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'display_name': 'E2E',
      }),
    );
    expect(response.statusCode, 201, reason: 'đăng ký user thử trên backend');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    token = body['token'] as String;
    userId = (body['user'] as Map<String, dynamic>)['id'] as String;
  });

  Future<List<Map<String, dynamic>>> serverSeries(String rootId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/todos?limit=100&parent_id=null'),
      headers: authHeaders(),
    );
    expect(response.statusCode, 200);
    final items =
        (jsonDecode(response.body) as Map<String, dynamic>)['items'] as List;
    return items
        .cast<Map<String, dynamic>>()
        .where(
          (t) => t['id'] == rootId || t['recurrence_template_id'] == rootId,
        )
        .toList();
  }

  List<Map<String, dynamic>> liveAt(
    List<Map<String, dynamic>> rows,
    DateTime day,
  ) => rows.where((r) => r['scheduled_date'] == formatDateOnly(day)).toList();

  /// Một "thiết bị": Drift riêng + repository + SyncWorker nói chuyện HTTP thật.
  _Device newDevice() {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final dio = Dio(
      BaseOptions(
        baseUrl: '$_baseUrl/',
        headers: {'Authorization': 'Bearer $token'},
        contentType: 'application/json',
      ),
    );
    return _Device(
      db: db,
      repository: TodosRepository.forTesting(db, userId: userId),
      worker: SyncWorker.forTesting(
        database: db,
        client: ApiClientDio.forTesting(dio),
        userId: userId,
      ),
      userId: userId,
    );
  }

  Future<Todo> createDaily(_Device device, String title, DateTime day) async {
    final created = await device.act(
      () => device.repository.createLocalFirst({
        'title': title,
        'scheduled_date': formatDateOnly(day),
        'recurrence_type': 'daily',
        'recurrence_interval': 1,
      }),
    );
    return created.todo;
  }

  void evidence(String step, Object detail) =>
      // ignore: avoid_print
      print('[T8] $step → $detail');

  test(
    'T8.1–3 tick shows the rule, untick hides the next one, tick again reuses it',
    () async {
      final device = newDevice();
      addTearDown(device.close);
      final root = await createDaily(device, 'E2E Mỗi ngày', today);
      await device.sync();

      // 1. Tick → bản mới ghi "Mỗi ngày".
      final first = await device.act(
        () => device.repository.completeLocalFirst(root),
      );
      final next = first.nextRecurringTodo!;
      expect(next.repeatRowValue, 'Mỗi ngày');
      await device.sync();
      var rows = await serverSeries(root.id);
      final onServer = liveAt(rows, plus(1)).single;
      expect(onServer['id'], next.id);
      expect(onServer['recurrence_type'], 'daily');
      expect(onServer['status'], 'open');
      evidence(
        '1 tick',
        'next=${next.id} ngày ${formatDateOnly(plus(1))} '
            'nhãn="${next.repeatRowValue}" server rows=${rows.length}',
      );

      // 2. Bỏ tick → bản mới biến mất khỏi mọi danh sách (nhưng còn trên server).
      final reopened = await device.act(
        () => device.repository.uncompleteLocalFirst(first.todo),
      );
      await device.sync();
      rows = await serverSeries(root.id);
      final parked = liveAt(rows, plus(1)).single;
      expect(parked['id'], next.id);
      expect(parked['status'], 'archived');
      final visible = await device.repository.listLocal();
      expect(visible.where((t) => t.id == next.id), isEmpty);
      expect(
        (await device.repository.listLocal(
          includeArchived: true,
        )).any((t) => t.id == next.id),
        isTrue,
        reason: 'row đỗ vẫn nằm trong Drift để hồi sinh',
      );
      evidence(
        '2 untick',
        'server status=${parked['status']} listLocal ẩn=true rows=${rows.length}',
      );

      // 3. Tick lại → đúng 1 bản mới, cùng id.
      final second = await device.act(
        () => device.repository.completeLocalFirst(reopened),
      );
      expect(second.nextRecurringTodo!.id, next.id);
      await device.sync();
      rows = await serverSeries(root.id);
      final revived = liveAt(rows, plus(1)).single;
      expect(revived['id'], next.id);
      expect(revived['status'], 'open');
      expect(rows, hasLength(2), reason: 'gốc + đúng 1 occurrence');
      evidence(
        '3 tick lại',
        'cùng id=${revived['id']} status=${revived['status']} rows=${rows.length}',
      );
    },
    skip: skip,
  );

  test('T8.4 untick, move the original, tick: the next one follows', () async {
    final device = newDevice();
    addTearDown(device.close);
    final root = await createDaily(device, 'E2E đổi ngày', today);
    await device.sync();
    final first = await device.act(
      () => device.repository.completeLocalFirst(root),
    );
    await device.sync();
    final nextId = first.nextRecurringTodo!.id;
    final reopened = await device.act(
      () => device.repository.uncompleteLocalFirst(first.todo),
    );
    await device.sync();

    final moved = await device.act(
      () => device.repository.updateLocalFirst(reopened, {
        'scheduled_date': formatDateOnly(plus(5)),
      }),
    );
    final second = await device.act(
      () => device.repository.completeLocalFirst(moved),
    );
    await device.sync();

    expect(second.nextRecurringTodo!.id, nextId);
    final rows = await serverSeries(root.id);
    expect(rows, hasLength(2), reason: 'không có bản thừa');
    expect(liveAt(rows, plus(1)), isEmpty, reason: 'slot cũ đã trống');
    final dest = liveAt(rows, plus(6)).single;
    expect(dest['id'], nextId);
    expect(dest['status'], 'open');
    evidence(
      '4 đổi ngày',
      'id=$nextId dời tới ${dest['scheduled_date']} rows=${rows.length}',
    );
  }, skip: skip);

  test('T8.5 a double tap creates exactly one next occurrence', () async {
    final device = newDevice();
    addTearDown(device.close);
    final root = await createDaily(device, 'E2E chạm đúp', today);
    await device.sync();

    final results = await Future.wait([
      device.act(() => device.repository.completeLocalFirst(root)),
      device.act(() => device.repository.completeLocalFirst(root)),
    ]);
    await device.sync();

    final ids = results
        .map((r) => r.nextRecurringTodo?.id)
        .whereType<String>()
        .toSet();
    expect(ids, hasLength(1));
    final rows = await serverSeries(root.id);
    expect(liveAt(rows, plus(1)), hasLength(1));
    expect(rows, hasLength(2));
    evidence('5 chạm đúp', 'ids=$ids server rows=${rows.length}');
  }, skip: skip);

  test(
    'T8.6 two devices tick offline then sync: one occurrence per date',
    () async {
      final a = newDevice();
      final b = newDevice();
      addTearDown(a.close);
      addTearDown(b.close);
      final root = await createDaily(a, 'E2E hai máy', today);
      await a.sync();
      await b.sync(); // máy B nhận bản gốc.

      // Cả hai hoàn thành khi offline: mỗi máy tự tạo occurrence kế tiếp.
      final doneA = await a.act(() => a.repository.completeLocalFirst(root));
      final rootOnB = (await b.repository.listLocal()).singleWhere(
        (t) => t.id == root.id,
      );
      final doneB = await b.act(() => b.repository.completeLocalFirst(rootOnB));
      expect(doneA.nextRecurringTodo!.id, isNot(doneB.nextRecurringTodo!.id));

      await a.sync(); // A lên trước → bản của A là chính tắc.
      await b.sync(); // B nhận conflict → nhận bản của A, bỏ bản của mình.
      await a.sync();

      final rows = await serverSeries(root.id);
      final slot = liveAt(rows, plus(1));
      expect(slot, hasLength(1));
      expect(slot.single['id'], doneA.nextRecurringTodo!.id);
      for (final device in [a, b]) {
        final local = await device.db.todosDao.getSeriesRows(
          root.id,
          userId: userId,
        );
        final atSlot = local
            .where(
              (r) =>
                  r.deletedAt == null &&
                  r.scheduledDate == formatDateOnly(plus(1)),
            )
            .toList();
        expect(atSlot, hasLength(1));
        expect(atSlot.single.id, doneA.nextRecurringTodo!.id);
        expect(
          await device.db.syncDao.getRowsForUser(userId: userId),
          isEmpty,
          reason: 'outbox sạch sau khi đồng bộ',
        );
      }
      evidence(
        '6 hai máy',
        'A=${doneA.nextRecurringTodo!.id} B=${doneB.nextRecurringTodo!.id} '
            '→ server giữ ${slot.single['id']} (1 bản), rows=${rows.length}',
      );
    },
    skip: skip,
  );

  test(
    'T8.7 another device parks it while this one only synced the create',
    () async {
      final a = newDevice();
      final b = newDevice();
      addTearDown(a.close);
      addTearDown(b.close);
      final root = await createDaily(a, 'E2E đỗ chéo', today);
      await a.sync();
      final done = await a.act(() => a.repository.completeLocalFirst(root));
      await a.sync();
      await b.sync();

      // B bỏ tick bản gốc (đỗ occurrence kế tiếp), A kéo về qua pull.
      final rootOnB = (await b.repository.listLocal()).singleWhere(
        (t) => t.id == root.id,
      );
      await b.act(() => b.repository.uncompleteLocalFirst(rootOnB));
      await b.sync();
      await a.sync();

      final parkedOnA = await a.db.todosDao.getTodoById(
        done.nextRecurringTodo!.id,
      );
      expect(parkedOnA!.status, 'archived');
      expect(
        (await a.repository.listLocal()).any(
          (t) => t.id == done.nextRecurringTodo!.id,
        ),
        isFalse,
      );
      final rows = await serverSeries(root.id);
      expect(liveAt(rows, plus(1)).single['status'], 'archived');
      evidence(
        '7 đỗ chéo máy',
        'A thấy B ${parkedOnA.status}, listLocal ẩn, server rows=${rows.length}',
      );
    },
    skip: skip,
  );
}

class _Device {
  _Device({
    required this.db,
    required this.repository,
    required this.worker,
    required this.userId,
  });

  final AppDatabase db;
  final TodosRepository repository;
  final SyncWorker worker;
  final String userId;

  /// Mọi thao tác ghi cục bộ hẹn sync nền sau 2s qua singleton: hủy để chỉ
  /// đồng bộ khi test chủ động gọi [sync].
  Future<T> act<T>(Future<T> Function() action) async {
    final result = await action();
    ConnectivitySync.instance.cancelPending();
    return result;
  }

  Future<void> sync() async {
    final result = await worker.sync();
    expect(result, SyncRunResult.success, reason: 'sync phải thành công');
  }

  Future<void> close() async {
    ConnectivitySync.instance.cancelPending();
    await db.close();
  }
}
