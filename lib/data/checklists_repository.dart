import 'dart:convert';

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
      return _sortCategories(categories, scope: scope);
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
    final body = <String, dynamic>{
      'name': name,
      if (slug != null && slug.isNotEmpty) 'slug': slug,
      'icon': icon,
      if (color != null) 'color': color,
      if (sortOrder != null) 'sort_order': sortOrder,
    };
    try {
      final resp = await _client.post('/checklists/categories', body: body);
      final category = ChecklistCategory.fromJson(
        (resp as Map<String, dynamic>)['category'] as Map<String, dynamic>,
      );
      await _cacheCategories([category]);
      return category;
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      final category = ChecklistCategory(
        id: newId(),
        userId: _userId,
        name: name,
        slug: slug == null || slug.isEmpty ? _slugFromName(name) : slug,
        icon: icon,
        color: jsonColor(color ?? '#4F46E5'),
        sortOrder: sortOrder ?? 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await _upsertCategoryWithSync(category, 'create');
      ConnectivitySync.instance.scheduleWriteSync();
      return category;
    }
  }

  Future<ChecklistCategory> updateCategory(
    ChecklistCategory current,
    Map<String, dynamic> body,
  ) async {
    if (current.isSystem) {
      throw const ApiException(403, 'read_only', 'read_only');
    }
    try {
      final resp = await _client.patch(
        '/checklists/categories/${current.id}',
        body: body,
      );
      final category = ChecklistCategory.fromJson(
        (resp as Map<String, dynamic>)['category'] as Map<String, dynamic>,
      );
      await _cacheCategories([category]);
      return category;
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      final updated = _patchCategory(current, body);
      await _upsertCategoryWithSync(updated, 'update');
      ConnectivitySync.instance.scheduleWriteSync();
      return updated;
    }
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
        },
      );
      final items = (resp as Map<String, dynamic>)['items'] as List;
      final templates = items
          .map((e) => Template.fromJson(e as Map<String, dynamic>))
          .toList();
      await _cacheTemplates(templates);
      return _filterTemplates(
        templates,
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
        rows.map(_templateRowToModel).toList(),
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
    final resp = await _client.get('/checklists/templates/$id');
    final map = resp as Map<String, dynamic>;
    final result = (
      template: Template.fromJson(map['template'] as Map<String, dynamic>),
      items: ((map['items'] as List?) ?? const [])
          .map((e) => TemplateItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
    await _db.checklistsDao.upsertTemplate(
      templateToCompanion(
        result.template,
        result.template.isSystem ? null : _userId,
      ),
    );
    for (final item in result.items) {
      await _db.checklistsDao.upsertTemplateItem(templateItemToCompanion(item));
    }
    return result;
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
    final body = <String, dynamic>{
      'title': title,
      if (description != null) 'description': description,
      if (icon != null) 'icon': icon,
      if (categoryId != null)
        'category_id': categoryId
      else if (category != null)
        'category': category,
      'items': items,
    };
    final resp = await _client.post('/checklists/templates', body: body);
    final map = resp as Map<String, dynamic>;
    final result = (
      template: Template.fromJson(map['template'] as Map<String, dynamic>),
      items: ((map['items'] as List?) ?? const [])
          .map((e) => TemplateItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
    await _db.checklistsDao.upsertTemplate(
      templateToCompanion(
        result.template,
        result.template.isSystem ? null : _userId,
      ),
    );
    for (final item in result.items) {
      await _db.checklistsDao.upsertTemplateItem(templateItemToCompanion(item));
    }
    return result;
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
    final resp = await _client.post(
      '/checklists/templates/$templateId/items',
      body: {
        'title': title,
        if (description != null) 'description': description,
        'is_required': isRequired,
      },
    );
    return TemplateItem.fromJson(
      (resp as Map<String, dynamic>)['item'] as Map<String, dynamic>,
    );
  }

  /// F-C7 Patch item.
  Future<TemplateItem> patchItem(
    String templateId,
    String itemId,
    Map<String, dynamic> body,
  ) async {
    final resp = await _client.patch(
      '/checklists/templates/$templateId/items/$itemId',
      body: body,
    );
    return TemplateItem.fromJson(
      (resp as Map<String, dynamic>)['item'] as Map<String, dynamic>,
    );
  }

  /// F-C8 Delete item.
  Future<void> deleteItem(String templateId, String itemId) async {
    await _client.delete('/checklists/templates/$templateId/items/$itemId');
  }

  /// F-C9 Reorder items.
  Future<List<TemplateItem>> reorderItems(
    String templateId,
    List<String> itemIds,
  ) async {
    final resp = await _client.post(
      '/checklists/templates/$templateId/items/reorder',
      body: {'item_ids': itemIds},
    );
    final items = (resp as Map<String, dynamic>)['items'] as List;
    return items
        .map((e) => TemplateItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── Runs ────────────────────────────────────────────────────

  /// F-C10 Start run.
  Future<({Run run, List<RunItem> items})> startRun({
    required String templateId,
    String? name,
  }) async {
    final resp = await _client.post(
      '/checklists/runs',
      body: {'template_id': templateId, if (name != null) 'name': name},
    );
    final map = resp as Map<String, dynamic>;
    return (
      run: Run.fromJson(map['run'] as Map<String, dynamic>),
      items: ((map['items'] as List?) ?? const [])
          .map((e) => RunItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// F-C11 List runs.
  Future<({List<Run> items, String? nextCursor})> listRuns({
    String? cursor,
    int? limit,
    String? status,
  }) async {
    final resp = await _client.get(
      '/checklists/runs',
      query: {
        if (cursor != null) 'cursor': cursor,
        if (limit != null) 'limit': limit,
        if (status != null) 'status': status,
      },
    );
    final map = resp as Map<String, dynamic>;
    return (
      items: (map['items'] as List)
          .map((e) => Run.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: map['nextCursor'] as String?,
    );
  }

  /// F-C12 Get run detail.
  Future<({Run run, List<RunItem> items})> getRun(String id) async {
    final resp = await _client.get('/checklists/runs/$id');
    final map = resp as Map<String, dynamic>;
    return (
      run: Run.fromJson(map['run'] as Map<String, dynamic>),
      items: ((map['items'] as List?) ?? const [])
          .map((e) => RunItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// F-C13 Update run item (mark progress).
  Future<RunItem> updateRunItem(
    String runId,
    String itemId, {
    required String status,
    String? note,
  }) async {
    final resp = await _client.patch(
      '/checklists/runs/$runId/items/$itemId',
      body: {'status': status, if (note != null) 'note': note},
    );
    return RunItem.fromJson(
      (resp as Map<String, dynamic>)['item'] as Map<String, dynamic>,
    );
  }

  /// F-C14 Complete run.
  Future<void> completeRun(String id) async {
    await _client.post('/checklists/runs/$id/complete', body: const {});
  }

  /// F-C15 Abandon run.
  Future<void> abandonRun(String id) async {
    await _client.post('/checklists/runs/$id/abandon', body: const {});
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

  Template _templateRowToModel(TemplateRow row) {
    return Template(
      id: row.id,
      title: row.title,
      description: row.description,
      icon: row.icon,
      category: row.category,
      categoryId: row.categoryId,
      isSystem: row.isSystem,
      timesUsed: row.timesUsed,
      lastUsedAt: jsonDateNullable(row.lastUsedAt),
      createdAt: jsonDate(row.createdAt),
      updatedAt: jsonDate(row.updatedAt),
    );
  }

  List<ChecklistCategory> _sortCategories(
    List<ChecklistCategory> categories, {
    required String scope,
  }) {
    final filtered = categories.where((category) {
      if (scope == 'own') return !category.isSystem;
      if (scope == 'system') return category.isSystem;
      return true;
    }).toList();
    filtered.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return filtered;
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
    filtered.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return filtered;
  }

  bool? _scopeIsSystem(String scope) {
    if (scope == 'own') return false;
    if (scope == 'system') return true;
    return null;
  }

  String _slugFromName(String name) {
    return name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}
