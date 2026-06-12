import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../sync/connectivity_sync.dart';
import '../sync/sync_payload.dart';
import '../utils/json_utils.dart';
import '../utils/uuid_utils.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'auth_storage.dart';
import 'local/database.dart';
import 'local/model_converters.dart';

class TagsRepository {
  TagsRepository._();
  static final TagsRepository instance = TagsRepository._();

  final ApiClient _client = ApiClient.instance;
  final AppDatabase _db = AppDatabase.instance;

  String get _userId =>
      AuthStorage.instance.currentUserJson?['id'] as String? ?? '';

  Future<List<Tag>> list({
    String scope = 'all',
    int limit = 100,
    String? q,
  }) async {
    try {
      final resp = await _client.get(
        '/tags',
        query: {
          'scope': scope,
          'limit': limit,
          if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        },
      );
      final items =
          ((resp as Map<String, dynamic>)['items'] as List? ?? const [])
              .map((e) => Tag.fromJson(e as Map<String, dynamic>))
              .toList();
      await _cacheTags(items);
      return items;
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      final rows = await _db.todosDao.getTags(
        q: q,
        onlyUsedByTodos: scope == 'todo',
      );
      return rows.map(_tagRowToModel).take(limit).toList();
    }
  }

  Future<List<Tag>> suggestions({
    required String scope,
    int limit = 20,
    String? q,
  }) async {
    try {
      final resp = await _client.get(
        '/tags/suggestions',
        query: {
          'scope': scope,
          'limit': limit,
          if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        },
      );
      final items =
          ((resp as Map<String, dynamic>)['items'] as List? ?? const [])
              .map((e) => Tag.fromJson(e as Map<String, dynamic>))
              .toList();
      await _cacheTags(items);
      return items;
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      return list(scope: scope, limit: limit, q: q);
    }
  }

  Future<Tag> create({required String name, required Color color}) async {
    final normalized = normalizeTagName(name);
    if (normalized.isEmpty) {
      throw const ApiException(400, 'bad_input', 'bad_input');
    }
    try {
      final resp = await _client.post(
        '/tags',
        body: {'name': normalized, 'color': formatColorHex(color)},
      );
      final tag = Tag.fromJson(
        (resp as Map<String, dynamic>)['tag'] as Map<String, dynamic>,
      );
      await _cacheTags([tag]);
      return tag;
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      return createLocal(name: normalized, color: color);
    }
  }

  Future<Tag> createLocal({required String name, required Color color}) async {
    final normalized = normalizeTagName(name);
    if (normalized.isEmpty) {
      throw const ApiException(400, 'bad_input', 'bad_input');
    }

    final existing = await _db.todosDao.findTagByNameInsensitive(
      normalized,
      _userId,
    );
    if (existing != null) return _tagRowToModel(existing);

    final tombstone = await _db.todosDao.findSoftDeletedTagByNameInsensitive(
      normalized,
      _userId,
    );

    final now = DateTime.now().toUtc();
    final tag = Tag(
      id: tombstone?.id ?? newId(),
      userId: _userId,
      name: tombstone?.name ?? normalized,
      color: color,
      createdAt: tombstone == null
          ? now
          : jsonDateNullable(tombstone.createdAt),
      updatedAt: now,
      deletedAt: null,
    );
    await _db.todosDao.upsertTag(tagToCompanion(tag, _userId));
    await _db.syncDao.enqueueSyncOp(
      entityType: 'tag',
      entityId: tag.id,
      operation: 'create',
      payload: SyncPayload.encode(
        SyncPayload.fromTag((await _db.todosDao.getTagById(tag.id))!),
      ),
    );
    ConnectivitySync.instance.scheduleWriteSync();
    return tag;
  }

  Future<Tag> update(Tag current, {String? name, Color? color}) async {
    final body = <String, dynamic>{
      if (name != null) 'name': normalizeTagName(name),
      if (color != null) 'color': formatColorHex(color),
    };
    try {
      final resp = await _client.patch('/tags/${current.id}', body: body);
      final tag = Tag.fromJson(
        (resp as Map<String, dynamic>)['tag'] as Map<String, dynamic>,
      );
      await _cacheTags([tag]);
      return tag;
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      final now = DateTime.now().toUtc();
      final tag = Tag(
        id: current.id,
        userId: current.userId ?? _userId,
        name: body['name'] as String? ?? current.name,
        color: color ?? current.color,
        createdAt: current.createdAt,
        updatedAt: now,
      );
      await _db.todosDao.upsertTag(tagToCompanion(tag, _userId));
      await _enqueueTagUpdate(tag.id, operation: 'update');
      ConnectivitySync.instance.scheduleWriteSync();
      return tag;
    }
  }

  Future<void> delete(Tag tag) async {
    final now = nowIso();
    try {
      await _client.delete('/tags/${tag.id}');
      await _db.todosDao.softDeleteTag(tag.id, now);
    } on ApiException catch (e) {
      if (e.code != 'no_connection') rethrow;
      await _db.todosDao.softDeleteTag(tag.id, now);
      await _db.syncDao.enqueueSyncOp(
        entityType: 'tag',
        entityId: tag.id,
        operation: 'delete',
        payload: jsonEncode({
          'id': tag.id,
          'deleted_at': now,
          'updated_at': now,
        }),
      );
      ConnectivitySync.instance.scheduleWriteSync();
    }
  }

  Future<void> _cacheTags(List<Tag> tags) async {
    await _db.todosDao.upsertTags(
      tags.map((tag) => tagToCompanion(tag, _userId)).toList(),
    );
  }

  Future<void> _enqueueTagUpdate(
    String tagId, {
    required String operation,
  }) async {
    final row = await _db.todosDao.getTagById(tagId);
    if (row == null) return;
    await _db.syncDao.enqueueSyncOp(
      entityType: 'tag',
      entityId: tagId,
      operation: operation,
      payload: SyncPayload.encode(SyncPayload.fromTag(row)),
    );
  }

  static String normalizeTagName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  Tag _tagRowToModel(TagRow row) {
    return Tag(
      id: row.id,
      userId: row.userId,
      name: row.name,
      color: jsonColor(row.color),
      createdAt: jsonDateNullable(row.createdAt),
      updatedAt: jsonDateNullable(row.updatedAt),
      deletedAt: jsonDateNullable(row.deletedAt),
    );
  }
}
