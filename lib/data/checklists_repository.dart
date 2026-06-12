import 'dart:convert';

import 'package:drift/drift.dart';

import '../models/checklist_category.dart';
import '../models/run.dart';
import '../models/run_item.dart';
import '../models/template.dart';
import '../models/template_item.dart';
import '../sync/connectivity_sync.dart';
import '../sync/sync_payload.dart';
import '../utils/json_utils.dart';
import '../utils/uuid_utils.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'auth_storage.dart';
import 'local/database.dart';
import 'local/model_converters.dart';

/// Repository cho Group C — Checklists (Templates + Runs). 16 endpoint F-C1..F-C16.
class ChecklistsRepository {
  ChecklistsRepository._();
  static final ChecklistsRepository instance = ChecklistsRepository._();
  final ApiClient _client = ApiClient.instance;
  final AppDatabase _db = AppDatabase.instance;

  String get _userId =>
      AuthStorage.instance.currentUserJson?['id'] as String? ?? '';

  // ─── Categories ──────────────────────────────────────────────

  Future<List<ChecklistCategory>> listCategories({String scope = 'all'}) async {
    try {
      final resp = await _client.get(
        '/checklists/categories',
        query: {'scope': scope},
      );
      final items = (resp as Map<String, dynamic>)['items'] as List;
      final categories = items
          .map((e) => ChecklistCategory.fromJson(e as Map<String, dynamic>))
          .toList();
      await _cacheCategories(categories);
      final rows = await _db.checklistsDao.getCategories(scope: scope);
      return rows.map(_categoryRowToModel).toList();
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      final rows = await _db.checklistsDao.getCategories(scope: scope);
      return rows.map(_categoryRowToModel).toList();
    }
  }

  Future<ChecklistCategory> getCategory(String id) async {
    try {
      final resp = await _client.get('/checklists/categories/$id');
      final category = ChecklistCategory.fromJson(
        (resp as Map<String, dynamic>)['category'] as Map<String, dynamic>,
      );
      await _cacheCategories([category]);
      return category;
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      final row = await _db.checklistsDao.getCategoryById(id);
      if (row == null) throw const ApiException(404, 'not_found', 'not_found');
      return _categoryRowToModel(row);
    }
  }

  Future<ChecklistCategory> createCategory({
    required String name,
    String? slug,
    String? icon,
    String? color,
    int? sortOrder,
  }) async {
    final id = newId();
    final now = DateTime.now().toUtc();
    final category = ChecklistCategory(
      id: id,
      userId: _userId,
      name: name,
      slug: slug == null || slug.isEmpty
          ? _slugFromName(name, fallbackId: id)
          : slug,
      icon: icon,
      color: jsonColor(color ?? '#4F46E5'),
      sortOrder: sortOrder ?? 0,
      createdAt: now,
      updatedAt: now,
    );
    await _upsertCategoryWithSync(category, 'create');
    ConnectivitySync.instance.scheduleWriteSync();
    return category;
  }

  Future<ChecklistCategory> updateCategory(
    ChecklistCategory current,
    Map<String, dynamic> body,
  ) async {
    if (current.isSystem) {
      throw const ApiException(403, 'read_only', 'read_only');
    }
    final updated = _patchCategory(current, body);
    await _upsertCategoryWithSync(updated, 'update');
    ConnectivitySync.instance.scheduleWriteSync();
    return updated;
  }

  Future<void> deleteCategory(ChecklistCategory category) async {
    if (category.isSystem) {
      throw const ApiException(403, 'read_only', 'read_only');
    }
    final now = nowIso();
    try {
      await _client.delete('/checklists/categories/${category.id}');
      await _db.checklistsDao.softDeleteCategory(category.id, now);
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      await _db.checklistsDao.softDeleteCategory(category.id, now);
      await _db.syncDao.enqueueSyncOp(
        entityType: 'checklist_category',
        entityId: category.id,
        operation: 'delete',
        payload: jsonEncode({
          'id': category.id,
          'deleted_at': now,
          'updated_at': now,
        }),
      );
      ConnectivitySync.instance.scheduleWriteSync();
    }
  }

  // ─── Templates ───────────────────────────────────────────────

  /// F-C1 List Templates.
  Future<List<Template>> listTemplates({
    String scope = 'all',
    String? category,
    String? categoryId,
    bool uncategorized = false,
  }) async {
    try {
      final resp = await _client.get(
        '/checklists/templates',
        query: {
          'scope': scope,
          if (categoryId != null) 'category_id': categoryId,
          if (categoryId == null && category != null) 'category': category,
          if (uncategorized) 'uncategorized': true,
        },
      );
      final items = (resp as Map<String, dynamic>)['items'] as List;
      final templates = items
          .map((e) => Template.fromJson(e as Map<String, dynamic>))
          .toList();
      await _cacheTemplates(templates);
      await _cacheTemplateItemsFromListPayload(items);
      return _listLocalTemplates(
        scope: scope,
        category: category,
        categoryId: categoryId,
        uncategorized: uncategorized,
      );
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      final rows = await _db.checklistsDao.getTemplates(
        isSystem: _scopeIsSystem(scope),
        categoryId: categoryId,
        uncategorized: uncategorized,
      );
      return _filterTemplates(
        await _templateRowsToModels(rows),
        scope: scope,
        category: category,
        categoryId: categoryId,
        uncategorized: uncategorized,
      );
    }
  }

  /// F-C2 Get template detail.
  Future<({Template template, List<TemplateItem> items})> getTemplate(
    String id,
  ) async {
    try {
      final resp = await _client.get('/checklists/templates/$id');
      final map = resp as Map<String, dynamic>;
      final result = (
        template: Template.fromJson(map['template'] as Map<String, dynamic>),
        items: ((map['items'] as List?) ?? const [])
            .map((e) => TemplateItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      await _cacheTemplate(result.template, result.items);
      return result;
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      return _getTemplateLocal(id);
    }
  }

  /// F-C3 Create user template (kèm items inline).
  Future<({Template template, List<TemplateItem> items})> createTemplate({
    required String title,
    String? description,
    String? icon,
    String? category,
    String? categoryId,
    required List<Map<String, dynamic>> items,
  }) async {
    final templateId = newId();
    final now = DateTime.now().toUtc();
    final template = Template(
      id: templateId,
      title: title,
      description: description,
      icon: icon,
      category: category,
      categoryId: categoryId,
      sortOrder: await _nextTemplateSortOrder(categoryId),
      isSystem: false,
      createdAt: now,
      updatedAt: now,
    );

    final templateItems = <TemplateItem>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      templateItems.add(
        TemplateItem(
          id: newId(),
          templateId: templateId,
          position: i + 1,
          title: item['title'] as String,
          description: item['description'] as String?,
          isRequired: item['is_required'] as bool? ?? true,
        ),
      );
    }

    await _db.transaction(() async {
      await _db.checklistsDao.upsertTemplate(
        templateToCompanion(template, _userId),
      );
      for (final item in templateItems) {
        await _db.checklistsDao.upsertTemplateItem(
          templateItemToCompanion(item),
        );
      }
      final templateRow = await _db.checklistsDao.getTemplateById(template.id);
      if (templateRow != null) {
        await _db.syncDao.enqueueSyncOp(
          entityType: 'checklist_template',
          entityId: template.id,
          operation: 'create',
          payload: SyncPayload.encode(SyncPayload.fromTemplate(templateRow)),
        );
      }
      for (final item in templateItems) {
        final row = await _db.checklistsDao.getTemplateItemById(item.id);
        if (row == null) continue;
        await _db.syncDao.enqueueSyncOp(
          entityType: 'checklist_template_item',
          entityId: item.id,
          operation: 'create',
          payload: SyncPayload.encode(SyncPayload.fromTemplateItem(row)),
        );
      }
    });
    ConnectivitySync.instance.scheduleWriteSync();
    return (template: template, items: templateItems);
  }

  /// F-C4 Update template.
  Future<Template> updateTemplate(String id, Map<String, dynamic> body) async {
    final resp = await _client.patch('/checklists/templates/$id', body: body);
    final template = Template.fromJson(
      (resp as Map<String, dynamic>)['template'] as Map<String, dynamic>,
    );
    await _db.checklistsDao.upsertTemplate(
      templateToCompanion(template, template.isSystem ? null : _userId),
    );
    return template;
  }

  /// F-C5 Delete template.
  Future<void> deleteTemplate(String id) async {
    await _client.delete('/checklists/templates/$id');
  }

  /// F-C6 Add item.
  Future<TemplateItem> addItem(
    String templateId, {
    required String title,
    String? description,
    bool isRequired = true,
  }) async {
    final nextPosition = await _nextTemplateItemPosition(templateId);
    final item = TemplateItem(
      id: newId(),
      templateId: templateId,
      position: nextPosition,
      title: title,
      description: description,
      isRequired: isRequired,
    );
    await _upsertTemplateItemWithSync(item, 'create');
    ConnectivitySync.instance.scheduleWriteSync();
    return item;
  }

  /// F-C7 Patch item.
  Future<TemplateItem> patchItem(
    String templateId,
    String itemId,
    Map<String, dynamic> body,
  ) async {
    final row = await _db.checklistsDao.getTemplateItemById(itemId);
    if (row == null) throw const ApiException(404, 'not_found', 'not_found');
    final now = nowIso();
    await _db.checklistsDao.updateTemplateItemFields(
      itemId,
      title: body.containsKey('title') ? body['title'] as String? : null,
      description: body.containsKey('description')
          ? body['description'] as String?
          : null,
      writeDescription: body.containsKey('description'),
      isRequired: body.containsKey('is_required')
          ? body['is_required'] as bool?
          : null,
      orderIndex: body.containsKey('position')
          ? (body['position'] as num?)?.toInt()
          : null,
      updatedAt: now,
    );
    await _enqueueTemplateItemUpdate(itemId);
    ConnectivitySync.instance.scheduleWriteSync();
    final updated = await _db.checklistsDao.getTemplateItemById(itemId);
    if (updated == null) {
      throw const ApiException(404, 'not_found', 'not_found');
    }
    return _templateItemRowToModel(updated);
  }

  /// F-C8 Delete item.
  Future<void> deleteItem(String templateId, String itemId) async {
    final now = nowIso();
    await _db.checklistsDao.softDeleteTemplateItem(itemId, now);
    await _db.syncDao.enqueueSyncOp(
      entityType: 'checklist_template_item',
      entityId: itemId,
      operation: 'delete',
      payload: jsonEncode({'id': itemId, 'deleted_at': now, 'updated_at': now}),
    );
    ConnectivitySync.instance.scheduleWriteSync();
  }

  /// F-C9 Reorder items.
  Future<List<TemplateItem>> reorderItems(
    String templateId,
    List<String> itemIds,
  ) async {
    for (var i = 0; i < itemIds.length; i++) {
      await _db.checklistsDao.updateTemplateItemFields(
        itemIds[i],
        orderIndex: i + 1,
        updatedAt: nowIso(),
      );
      await _enqueueTemplateItemUpdate(itemIds[i]);
    }
    ConnectivitySync.instance.scheduleWriteSync();
    final rows = await _db.checklistsDao.getItemsForTemplate(templateId);
    return rows.map(_templateItemRowToModel).toList();
  }

  Future<List<Template>> reorderTemplates({
    required List<Template> templates,
    String? categoryId,
    bool uncategorized = false,
  }) async {
    if (templates.isEmpty) return templates;
    final ordered = [
      for (var i = 0; i < templates.length; i++)
        templates[i].copyWith(sortOrder: i + 1),
    ];

    await _saveTemplateOrders(ordered);
    ConnectivitySync.instance.scheduleWriteSync();
    return ordered;
  }

  // ─── Runs ────────────────────────────────────────────────────

  /// F-C10 Start run.
  Future<({Run run, List<RunItem> items})> startRun({
    required String templateId,
    String? name,
  }) async {
    final existing = await _findLocalInProgressRunForTemplate(templateId);
    if (existing != null) {
      final items = await _db.checklistsDao.getItemsForRun(existing.id);
      return (run: existing, items: items.map(_runItemRowToModel).toList());
    }
    return _startRunLocal(templateId: templateId, name: name);
  }

  /// F-C11 List runs.
  Future<({List<Run> items, String? nextCursor})> listRuns({
    String? cursor,
    int? limit,
    String? status,
    String? templateId,
  }) async {
    try {
      final resp = await _client.get(
        '/checklists/runs',
        query: {
          if (cursor != null) 'cursor': cursor,
          if (limit != null) 'limit': limit,
          if (status != null) 'status': status,
          if (templateId != null) 'template_id': templateId,
        },
      );
      final map = resp as Map<String, dynamic>;
      final items = (map['items'] as List)
          .map((e) => Run.fromJson(e as Map<String, dynamic>))
          .toList();
      await _cacheRuns(items);
      return (items: items, nextCursor: map['nextCursor'] as String?);
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      final rows = await _db.checklistsDao.getRuns(
        limit: limit ?? 20,
        status: status,
        templateId: templateId,
      );
      return (items: rows.map(_runRowToModel).toList(), nextCursor: null);
    }
  }

  /// F-C12 Get run detail.
  Future<({Run run, List<RunItem> items})> getRun(String id) async {
    try {
      final resp = await _client.get('/checklists/runs/$id');
      final map = resp as Map<String, dynamic>;
      final result = (
        run: Run.fromJson(map['run'] as Map<String, dynamic>),
        items: ((map['items'] as List?) ?? const [])
            .map((e) => RunItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      await _cacheRun(result.run, result.items);
      return result;
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      final row = await _db.checklistsDao.getRunById(id);
      if (row == null) throw const ApiException(404, 'not_found', 'not_found');
      final items = await _db.checklistsDao.getItemsForRun(id);
      return (
        run: _runRowToModel(row),
        items: items.map(_runItemRowToModel).toList(),
      );
    }
  }

  /// F-C13 Update run item (mark progress).
  Future<RunItem> updateRunItem(
    String runId,
    String itemId, {
    required String status,
    String? note,
  }) async {
    final row = await _db.checklistsDao.getRunItemById(itemId);
    if (row == null) throw const ApiException(404, 'not_found', 'not_found');
    final now = nowIso();
    final completedAt = status == RunItemStatus.done.backendValue ? now : null;
    await _db.checklistsDao.updateRunItemFields(
      itemId,
      status: status,
      completedAt: completedAt,
      note: note,
      updatedAt: now,
    );
    await _enqueueRunItemUpdate(itemId);
    ConnectivitySync.instance.scheduleWriteSync();
    final updated = await _db.checklistsDao.getRunItemById(itemId);
    if (updated == null) {
      throw const ApiException(404, 'not_found', 'not_found');
    }
    return _runItemRowToModel(updated);
  }

  /// F-C14 Complete run.
  Future<void> completeRun(String id, {int? durationMs}) async {
    _validateDurationMs(durationMs);
    final existing = await _db.checklistsDao.getRunById(id);
    if (existing?.status == RunStatus.completed.backendValue) return;
    await _markRunCompleted(id, durationMs: durationMs);
    await _enqueueRunUpdate(id);
    ConnectivitySync.instance.scheduleWriteSync();
  }

  /// F-C15 Abandon run.
  Future<void> abandonRun(String id) async {
    await _markRunAbandoned(id);
    await _enqueueRunUpdate(id);
    ConnectivitySync.instance.scheduleWriteSync();
  }

  /// F-C16 Delete run (hard delete).
  Future<void> deleteRun(String id) async {
    await _client.delete('/checklists/runs/$id');
  }

  // ─── Local helpers ───────────────────────────────────────────

  Future<void> _cacheCategories(List<ChecklistCategory> categories) async {
    if (categories.isEmpty) return;
    await _db.checklistsDao.upsertCategories(
      categories.map(checklistCategoryToCompanion).toList(),
    );
  }

  Future<void> _cacheTemplates(List<Template> templates) async {
    if (templates.isEmpty) return;
    await _db.checklistsDao.upsertTemplates(
      templates
          .map(
            (template) => templateToCompanion(
              template,
              template.isSystem ? null : _userId,
            ),
          )
          .toList(),
    );
  }

  Future<void> _cacheTemplate(
    Template template,
    List<TemplateItem> items,
  ) async {
    await _db.checklistsDao.upsertTemplate(
      templateToCompanion(template, template.isSystem ? null : _userId),
    );
    for (final item in items) {
      await _db.checklistsDao.upsertTemplateItem(templateItemToCompanion(item));
    }
  }

  Future<void> _cacheTemplateItemsFromListPayload(List<dynamic> items) async {
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final rawItems = item['items'] ?? item['template_items'];
      if (rawItems is! List) continue;
      for (final rawItem in rawItems) {
        if (rawItem is! Map<String, dynamic>) continue;
        await _db.checklistsDao.upsertTemplateItem(
          templateItemToCompanion(TemplateItem.fromJson(rawItem)),
        );
      }
    }
  }

  Future<void> _cacheRuns(List<Run> runs) async {
    for (final run in runs) {
      await _db.checklistsDao.upsertRun(runToCompanion(run, _userId));
    }
  }

  Future<void> _cacheRun(Run run, List<RunItem> items) async {
    await _db.checklistsDao.upsertRun(runToCompanion(run, _userId));
    for (final item in items) {
      await _db.checklistsDao.upsertRunItem(runItemToCompanion(item));
    }
  }

  Future<({Run run, List<RunItem> items})> _startRunLocal({
    required String templateId,
    String? name,
  }) async {
    var template = await _db.checklistsDao.getTemplateById(templateId);
    var templateItems = await _db.checklistsDao.getItemsForTemplate(templateId);
    if (template == null || templateItems.isEmpty) {
      try {
        final remote = await _fetchAndCacheTemplate(templateId);
        template = await _db.checklistsDao.getTemplateById(remote.template.id);
        templateItems = await _db.checklistsDao.getItemsForTemplate(templateId);
      } on ApiException catch (e) {
        if (e.code != 'no_connection') rethrow;
      }
    }
    if (template == null) {
      throw const ApiException(404, 'not_found', 'not_found');
    }
    if (templateItems.isEmpty) {
      throw const ApiException(400, 'empty_template', 'Checklist chưa có bước');
    }
    final now = DateTime.now().toUtc();
    final run = Run(
      id: newId(),
      templateId: templateId,
      name: name ?? template.title,
      templateTitle: template.title,
      status: RunStatus.inProgress,
      startedAt: now,
    );
    final items = [
      for (final item in templateItems)
        RunItem(
          id: newId(),
          runId: run.id,
          templateItemId: item.id,
          title: item.title,
          description: item.description,
          isRequired: item.isRequired,
          position: item.orderIndex,
        ),
    ];

    await _db.transaction(() async {
      await _db.checklistsDao.upsertRun(runToCompanion(run, _userId));
      for (final item in items) {
        await _db.checklistsDao.upsertRunItem(runItemToCompanion(item));
      }
      final row = await _db.checklistsDao.getRunById(run.id);
      if (row != null) {
        await _db.syncDao.enqueueSyncOp(
          entityType: 'checklist_run',
          entityId: run.id,
          operation: 'create',
          payload: SyncPayload.encode(SyncPayload.fromRun(row)),
        );
      }
      for (final item in items) {
        final row = await (_db.select(
          _db.checklistRunItemsTable,
        )..where((r) => r.id.equals(item.id))).getSingleOrNull();
        if (row == null) continue;
        await _db.syncDao.enqueueSyncOp(
          entityType: 'checklist_run_item',
          entityId: item.id,
          operation: 'create',
          payload: SyncPayload.encode(SyncPayload.fromRunItem(row)),
        );
      }
    });
    ConnectivitySync.instance.scheduleWriteSync();
    return (run: run, items: items);
  }

  Future<({Template template, List<TemplateItem> items})>
  _fetchAndCacheTemplate(String id) async {
    final resp = await _client.get('/checklists/templates/$id');
    final map = resp as Map<String, dynamic>;
    final result = (
      template: Template.fromJson(map['template'] as Map<String, dynamic>),
      items: ((map['items'] as List?) ?? const [])
          .map((e) => TemplateItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
    await _cacheTemplate(result.template, result.items);
    return result;
  }

  Future<({Template template, List<TemplateItem> items})> _getTemplateLocal(
    String id,
  ) async {
    final template = await _db.checklistsDao.getTemplateById(id);
    if (template == null) {
      throw const ApiException(404, 'not_found', 'not_found');
    }
    final items = await _db.checklistsDao.getItemsForTemplate(id);
    return (
      template: _templateRowToModel(template),
      items: items.map(_templateItemRowToModel).toList(),
    );
  }

  Future<int> _nextTemplateItemPosition(String templateId) async {
    final rows = await _db.checklistsDao.getItemsForTemplate(templateId);
    var maxPosition = 0;
    for (final row in rows) {
      if (row.orderIndex > maxPosition) maxPosition = row.orderIndex;
    }
    return maxPosition + 1;
  }

  Future<void> _upsertTemplateItemWithSync(
    TemplateItem item,
    String operation,
  ) async {
    await _db.checklistsDao.upsertTemplateItem(templateItemToCompanion(item));
    final row = await _db.checklistsDao.getTemplateItemById(item.id);
    if (row == null) return;
    await _db.syncDao.enqueueSyncOp(
      entityType: 'checklist_template_item',
      entityId: item.id,
      operation: operation,
      payload: SyncPayload.encode(SyncPayload.fromTemplateItem(row)),
    );
  }

  Future<void> _enqueueTemplateItemUpdate(String id) async {
    final row = await _db.checklistsDao.getTemplateItemById(id);
    if (row == null) return;
    await _db.syncDao.enqueueSyncOp(
      entityType: 'checklist_template_item',
      entityId: id,
      operation: 'update',
      payload: SyncPayload.encode(SyncPayload.fromTemplateItem(row)),
    );
  }

  Future<void> _enqueueRunItemUpdate(String id) async {
    final row = await _db.checklistsDao.getRunItemById(id);
    if (row == null) return;
    await _db.syncDao.enqueueSyncOp(
      entityType: 'checklist_run_item',
      entityId: id,
      operation: 'update',
      payload: SyncPayload.encode(SyncPayload.fromRunItem(row)),
    );
  }

  Future<void> _markRunCompleted(String id, {int? durationMs}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.checklistsDao.updateRunStatus(
      id,
      status: RunStatus.completed.backendValue,
      completedAt: now,
      durationMs: durationMs,
      writeDuration: true,
      updatedAt: now,
    );
  }

  Future<void> _markRunAbandoned(String id) async {
    final existing = await _db.checklistsDao.getRunById(id);
    if (existing?.status == RunStatus.completed.backendValue) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.checklistsDao.updateRunStatus(
      id,
      status: RunStatus.abandoned.backendValue,
      completedAt: null,
      durationMs: null,
      writeDuration: true,
      updatedAt: now,
    );
  }

  Future<void> _enqueueRunUpdate(String id) async {
    final row = await _db.checklistsDao.getRunById(id);
    if (row == null) return;
    await _db.syncDao.enqueueSyncOp(
      entityType: 'checklist_run',
      entityId: id,
      operation: 'update',
      payload: SyncPayload.encode(SyncPayload.fromRun(row)),
    );
  }

  void _validateDurationMs(int? durationMs) {
    if (durationMs == null || durationMs >= 0) return;
    throw const ApiException(400, 'bad_input', 'duration_ms invalid');
  }

  Future<Run?> _findLocalInProgressRunForTemplate(String templateId) async {
    final local = await _db.checklistsDao.getInProgressRunForTemplate(
      templateId,
    );
    return local == null ? null : _runRowToModel(local);
  }

  Future<void> _upsertCategoryWithSync(
    ChecklistCategory category,
    String operation,
  ) async {
    await _db.checklistsDao.upsertCategory(
      checklistCategoryToCompanion(category),
    );
    final row = await _db.checklistsDao.getCategoryById(category.id);
    if (row == null) return;
    await _db.syncDao.enqueueSyncOp(
      entityType: 'checklist_category',
      entityId: category.id,
      operation: operation,
      payload: SyncPayload.encode(SyncPayload.fromChecklistCategory(row)),
    );
  }

  Future<void> _saveTemplateOrders(List<Template> templates) async {
    final userId = _userId;
    final now = DateTime.now().toUtc().toIso8601String();
    for (final template in templates) {
      final existing = await _db.checklistsDao.getTemplateOrderForTemplate(
        userId: userId,
        templateId: template.id,
      );
      final orderId = existing?.id ?? newId();
      await _db.checklistsDao.upsertTemplateOrder(
        ChecklistTemplateOrdersTableCompanion(
          id: Value(orderId),
          userId: Value(userId),
          templateId: Value(template.id),
          sortOrder: Value(template.sortOrder),
          createdAt: Value(existing?.createdAt ?? now),
          updatedAt: Value(now),
          deletedAt: const Value(null),
        ),
      );
      final row = await _db.checklistsDao.getTemplateOrderById(orderId);
      if (row == null) continue;
      await _db.syncDao.enqueueSyncOp(
        entityType: 'checklist_template_order',
        entityId: orderId,
        operation: existing == null ? 'create' : 'update',
        payload: SyncPayload.encode(SyncPayload.fromTemplateOrder(row)),
      );
    }
  }

  ChecklistCategory _categoryRowToModel(ChecklistCategoryRow row) {
    return ChecklistCategory(
      id: row.id,
      userId: row.userId,
      name: row.name,
      slug: row.slug,
      icon: row.icon,
      color: jsonColor(row.color),
      sortOrder: row.sortOrder,
      isSystem: row.isSystem,
      createdAt: jsonDate(row.createdAt),
      updatedAt: jsonDate(row.updatedAt),
      deletedAt: jsonDateNullable(row.deletedAt),
    );
  }

  ChecklistCategory _patchCategory(
    ChecklistCategory current,
    Map<String, dynamic> body,
  ) {
    final now = DateTime.now().toUtc();
    return ChecklistCategory(
      id: current.id,
      userId: current.userId,
      name: body.containsKey('name') ? body['name'] as String : current.name,
      slug: body.containsKey('slug')
          ? body['slug'] as String? ?? current.slug
          : current.slug,
      icon: body.containsKey('icon') ? body['icon'] as String? : current.icon,
      color: body.containsKey('color')
          ? jsonColor(body['color'] as String? ?? '#4F46E5')
          : current.color,
      sortOrder: body.containsKey('sort_order')
          ? (body['sort_order'] as num?)?.toInt() ?? current.sortOrder
          : current.sortOrder,
      isSystem: current.isSystem,
      createdAt: current.createdAt,
      updatedAt: now,
      deletedAt: current.deletedAt,
    );
  }

  Future<List<Template>> _templateRowsToModels(List<TemplateRow> rows) async {
    final orders = await _db.checklistsDao.getTemplateOrders(userId: _userId);
    final orderByTemplateId = {
      for (final order in orders) order.templateId: order.sortOrder,
    };
    return rows
        .map(
          (row) => _templateRowToModel(
            row,
            sortOrderOverride: orderByTemplateId[row.id],
          ),
        )
        .toList();
  }

  Future<List<Template>> _listLocalTemplates({
    required String scope,
    String? category,
    String? categoryId,
    required bool uncategorized,
  }) async {
    final rows = await _db.checklistsDao.getTemplates(
      isSystem: _scopeIsSystem(scope),
      categoryId: categoryId,
      uncategorized: uncategorized,
    );
    return _filterTemplates(
      await _templateRowsToModels(rows),
      scope: scope,
      category: category,
      categoryId: categoryId,
      uncategorized: uncategorized,
    );
  }

  Future<int> _nextTemplateSortOrder(String? categoryId) async {
    final existing = await _listLocalTemplates(
      scope: 'all',
      categoryId: categoryId,
      uncategorized: categoryId == null,
    );
    var maxOrder = 0;
    for (final template in existing) {
      if (template.sortOrder > maxOrder) maxOrder = template.sortOrder;
    }
    return maxOrder + 1;
  }

  Template _templateRowToModel(TemplateRow row, {int? sortOrderOverride}) {
    return Template(
      id: row.id,
      title: row.title,
      description: row.description,
      icon: row.icon,
      category: row.category,
      categoryId: row.categoryId,
      sortOrder: sortOrderOverride ?? row.sortOrder,
      isSystem: row.isSystem,
      timesUsed: row.timesUsed,
      lastUsedAt: jsonDateNullable(row.lastUsedAt),
      createdAt: jsonDate(row.createdAt),
      updatedAt: jsonDate(row.updatedAt),
    );
  }

  TemplateItem _templateItemRowToModel(TemplateItemRow row) {
    return TemplateItem(
      id: row.id,
      templateId: row.templateId,
      position: row.orderIndex,
      title: row.title,
      description: row.description,
      isRequired: row.isRequired,
    );
  }

  Run _runRowToModel(RunRow row) {
    return Run(
      id: row.id,
      templateId: row.templateId,
      name: row.name,
      status: RunStatus.parse(row.status),
      startedAt: jsonDate(row.createdAt),
      completedAt: jsonDateNullable(row.completedAt),
      durationMs: row.durationMs,
    );
  }

  RunItem _runItemRowToModel(RunItemRow row) {
    return RunItem(
      id: row.id,
      runId: row.runId,
      templateItemId: row.templateItemId ?? '',
      status: RunItemStatus.parse(row.status),
      title: row.title,
      isRequired: row.isRequired,
      position: row.orderIndex,
      completedAt: jsonDateNullable(row.completedAt),
      note: row.note,
    );
  }

  List<Template> _filterTemplates(
    List<Template> templates, {
    required String scope,
    String? category,
    String? categoryId,
    required bool uncategorized,
  }) {
    final filtered = templates.where((template) {
      if (scope == 'own' && template.isSystem) return false;
      if (scope == 'system' && !template.isSystem) return false;
      if (categoryId != null) return template.categoryId == categoryId;
      if (uncategorized) return template.categoryId == null;
      if (category != null) return template.category == category;
      return true;
    }).toList();
    filtered.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      final byUpdated = b.updatedAt.compareTo(a.updatedAt);
      if (byUpdated != 0) return byUpdated;
      final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      if (byTitle != 0) return byTitle;
      return a.id.compareTo(b.id);
    });
    return filtered;
  }

  bool? _scopeIsSystem(String scope) {
    if (scope == 'own') return false;
    if (scope == 'system') return true;
    return null;
  }

  String _slugFromName(String name, {required String fallbackId}) {
    final base = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final suffix = fallbackId.replaceAll('-', '').take(8);
    if (base.isEmpty) return 'category-$suffix';
    return '$base-$suffix';
  }
}

extension _StringTake on String {
  String take(int count) => length <= count ? this : substring(0, count);
}
