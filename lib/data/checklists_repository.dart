import '../models/run.dart';
import '../models/run_item.dart';
import '../models/template.dart';
import '../models/template_item.dart';
import 'api_client.dart';

/// Repository cho Group C — Checklists (Templates + Runs). 16 endpoint F-C1..F-C16.
class ChecklistsRepository {
  ChecklistsRepository._();
  static final ChecklistsRepository instance = ChecklistsRepository._();
  final ApiClient _client = ApiClient.instance;

  // ─── Templates ───────────────────────────────────────────────

  /// F-C1 List Templates.
  Future<List<Template>> listTemplates({
    String scope = 'all',
    String? category,
  }) async {
    final resp = await _client.get('/checklists/templates', query: {
      'scope': scope,
      if (category != null) 'category': category,
    });
    final items = (resp as Map<String, dynamic>)['items'] as List;
    return items.map((e) => Template.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// F-C2 Get template detail.
  Future<({Template template, List<TemplateItem> items})> getTemplate(String id) async {
    final resp = await _client.get('/checklists/templates/$id');
    final map = resp as Map<String, dynamic>;
    return (
      template: Template.fromJson(map['template'] as Map<String, dynamic>),
      items: ((map['items'] as List?) ?? const [])
          .map((e) => TemplateItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// F-C3 Create user template (kèm items inline).
  Future<({Template template, List<TemplateItem> items})> createTemplate({
    required String title,
    String? description,
    String? icon,
    String? category,
    required List<Map<String, dynamic>> items,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      if (description != null) 'description': description,
      if (icon != null) 'icon': icon,
      if (category != null) 'category': category,
      'items': items,
    };
    final resp = await _client.post('/checklists/templates', body: body);
    final map = resp as Map<String, dynamic>;
    return (
      template: Template.fromJson(map['template'] as Map<String, dynamic>),
      items: ((map['items'] as List?) ?? const [])
          .map((e) => TemplateItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// F-C4 Update template.
  Future<Template> updateTemplate(String id, Map<String, dynamic> body) async {
    final resp = await _client.patch('/checklists/templates/$id', body: body);
    return Template.fromJson((resp as Map<String, dynamic>)['template'] as Map<String, dynamic>);
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
        (resp as Map<String, dynamic>)['item'] as Map<String, dynamic>);
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
        (resp as Map<String, dynamic>)['item'] as Map<String, dynamic>);
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
    return items.map((e) => TemplateItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ─── Runs ────────────────────────────────────────────────────

  /// F-C10 Start run.
  Future<({Run run, List<RunItem> items})> startRun({
    required String templateId,
    String? name,
  }) async {
    final resp = await _client.post(
      '/checklists/runs',
      body: {
        'template_id': templateId,
        if (name != null) 'name': name,
      },
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
    final resp = await _client.get('/checklists/runs', query: {
      if (cursor != null) 'cursor': cursor,
      if (limit != null) 'limit': limit,
      if (status != null) 'status': status,
    });
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
      body: {
        'status': status,
        if (note != null) 'note': note,
      },
    );
    return RunItem.fromJson(
        (resp as Map<String, dynamic>)['item'] as Map<String, dynamic>);
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
}
