import 'package:uuid/uuid.dart';

/// UUID v7 generator — time-ordered for good DB locality.
const _uuid = Uuid();

/// Generate a new UUID v7 string for local entity IDs.
String newId() => _uuid.v7();

/// Current UTC ISO 8601 timestamp.
String nowIso() => DateTime.now().toUtc().toIso8601String();
