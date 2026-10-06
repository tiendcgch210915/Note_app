import 'package:flutter_quill/flutter_quill.dart';

const noteContentFormatPlain = 'plain';
const noteContentFormatQuill = 'quill_delta_v1';

const _allowedAttributes = <String>{
  'bold',
  'italic',
  'underline',
  'strike',
  'link',
  'header',
  'list',
  'blockquote',
  'code',
  'code-block',
};

Document noteDocumentFrom({Map<String, dynamic>? delta, String? plainText}) {
  final sanitized = sanitizeNoteDelta(delta);
  if (sanitized != null) {
    try {
      return Document.fromJson(
        (sanitized['ops'] as List)
            .map((operation) => Map<String, dynamic>.from(operation as Map))
            .toList(),
      );
    } catch (_) {
      // Fall back to the legacy plain-text mirror.
    }
  }
  final text = plainText ?? '';
  return Document.fromJson([
    {'insert': text.endsWith('\n') ? text : '$text\n'},
  ]);
}

Map<String, dynamic> noteDeltaFromDocument(Document document) {
  final raw = <String, dynamic>{'ops': document.toDelta().toJson()};
  return sanitizeNoteDelta(raw) ??
      const <String, dynamic>{
        'ops': [
          {'insert': '\n'},
        ],
      };
}

String notePlainTextFromDocument(Document document) {
  final text = document.toPlainText();
  return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
}

Map<String, dynamic>? sanitizeNoteDelta(dynamic value) {
  if (value is! Map) return null;
  final rawOps = value['ops'];
  if (rawOps is! List) return null;

  final operations = <Map<String, dynamic>>[];
  for (final rawOperation in rawOps) {
    if (rawOperation is! Map || !rawOperation.containsKey('insert')) continue;
    final insert = rawOperation['insert'];
    if (insert is! String) continue;

    final operation = <String, dynamic>{'insert': insert};
    final rawAttributes = rawOperation['attributes'];
    if (rawAttributes is Map) {
      final attributes = <String, dynamic>{};
      for (final entry in rawAttributes.entries) {
        final key = entry.key.toString();
        final attributeValue = entry.value;
        if (!_allowedAttributes.contains(key) || attributeValue == null) {
          continue;
        }
        if (key == 'link') {
          if (attributeValue is String) {
            if (attributeValue.trim().isNotEmpty) {
              attributes[key] = attributeValue;
            }
          }
          continue;
        }
        if (attributeValue is String ||
            attributeValue is num ||
            attributeValue is bool) {
          attributes[key] = attributeValue;
        }
      }
      if (attributes.isNotEmpty) operation['attributes'] = attributes;
    }
    operations.add(operation);
  }

  if (operations.isEmpty) {
    operations.add({'insert': '\n'});
  } else {
    final lastInsert = operations.last['insert'] as String;
    if (!lastInsert.endsWith('\n')) operations.add({'insert': '\n'});
  }
  return {'ops': operations};
}

bool noteDeltaContainsOnlyInsertOperations(Map<String, dynamic>? delta) {
  if (delta == null) return true;
  final rawOps = delta['ops'];
  return rawOps is List &&
      rawOps.every(
        (operation) =>
            operation is Map &&
            operation.containsKey('insert') &&
            !operation.containsKey('retain') &&
            !operation.containsKey('delete'),
      );
}
