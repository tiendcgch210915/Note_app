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
import 'package:todonote/models/template.dart';
import 'package:todonote/models/template_item.dart';
import 'package:todonote/screens/checklists/template_detail_screen.dart';
import 'package:todonote/sync/connectivity_sync.dart';
import 'package:todonote/widgets/primary_button.dart';

const _userId = 'user-1';
const _templateId = 't1';
final _t0 = DateTime.utc(2026, 7);

const _seedItem = TemplateItem(
  id: 'i1',
  templateId: _templateId,
  position: 1,
  title: 'Bước cũ',
);

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
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
          if (request.url.path.endsWith('/checklists/templates/$_templateId')) {
            return _json({
              'template': {
                'id': _templateId,
                'title': 'Checklist thử',
                'created_at': _t0.toIso8601String(),
                'updated_at': _t0.toIso8601String(),
              },
              'items': [
                {
                  'id': _seedItem.id,
                  'template_id': _templateId,
                  'position': _seedItem.position,
                  'title': _seedItem.title,
                  'is_required': true,
                },
              ],
            });
          }
          return _json({'items': <Object>[]});
        }),
      ),
    );
  }

  final WidgetTester tester;
  late final AppDatabase db;

  static const _secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  Future<void> seed() {
    // Ghi sync_queue cần user đã đăng nhập; giả lập kho khoá của hệ điều hành.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
    return tester.runAsync(() async {
      await AuthStorage.instance.saveUserJson({'id': _userId});
      await db.checklistsDao.upsertTemplate(
        templateToCompanion(
          Template(
            id: _templateId,
            title: 'Checklist thử',
            createdAt: _t0,
            updatedAt: _t0,
          ),
          _userId,
        ),
      );
      await db.checklistsDao.upsertTemplateItem(
        templateItemToCompanion(_seedItem),
      );
    });
  }

  /// Drift chạy bất đồng bộ thật: nhường event loop thật rồi mới pump.
  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openEditMode() async {
    await tester.pumpWidget(
      const MaterialApp(home: TemplateDetailScreen(templateId: _templateId)),
    );
    await settle();
    await tester.tap(find.byTooltip('Chỉnh sửa'));
    await settle();
  }

  Finder get dialogField => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );

  Future<void> dispose() async {
    ConnectivitySync.instance.cancelPending();
    ChecklistsRepository.testInstance = null;
    await tester.runAsync(() async {
      await AuthStorage.instance.clear();
      await db.close();
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  }
}

void main() {
  testWidgets('adding a step closes its dialog without framework errors', (
    tester,
  ) async {
    final env = _Env(tester);
    await env.seed();
    await env.openEditMode();

    await tester.tap(find.widgetWithText(PrimaryButton, 'Thêm bước'));
    await env.settle();
    await tester.enterText(env.dialogField, 'Bước mới');
    await tester.tap(find.widgetWithText(TextButton, 'Thêm'));
    // Dialog đang chạy hiệu ứng đóng: đây chính là lúc crash cũ xảy ra.
    await env.settle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Bước mới'), findsOneWidget);

    await env.dispose();
  });

  testWidgets('editing a step closes its dialog without framework errors', (
    tester,
  ) async {
    final env = _Env(tester);
    await env.seed();
    await env.openEditMode();

    await tester.tap(find.text('Bước cũ'));
    await env.settle();
    expect(find.widgetWithText(TextField, 'Bước cũ'), findsOneWidget);
    await tester.enterText(env.dialogField, 'Bước đã sửa');
    await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
    await env.settle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Bước đã sửa'), findsOneWidget);
    expect(find.text('Bước cũ'), findsNothing);

    await env.dispose();
  });

  testWidgets('cancelling the add dialog adds nothing and does not crash', (
    tester,
  ) async {
    final env = _Env(tester);
    await env.seed();
    await env.openEditMode();

    await tester.tap(find.widgetWithText(PrimaryButton, 'Thêm bước'));
    await env.settle();
    await tester.enterText(env.dialogField, 'Không lưu');
    await tester.tap(find.widgetWithText(TextButton, 'Hủy'));
    await env.settle();

    expect(tester.takeException(), isNull);
    expect(find.text('Không lưu'), findsNothing);

    await env.dispose();
  });
}
