class ApiConfig {
  ApiConfig._();

  static const String dartDefineName = 'TODO_NOTE_API_BASE_URL';

  static const String rawApiBaseUrl = String.fromEnvironment(
    dartDefineName,
    defaultValue: 'https://todo-note-h8s1.onrender.com/api/v1',
  );

  static final Uri apiBaseUri = _normalizeApiBaseUri(rawApiBaseUrl);

  static String get apiBaseUrl => apiBaseUri.toString();

  static Uri get healthUri => apiBaseUri.replace(path: '/health', query: null);

  static String get healthUrl => healthUri.toString();

  static Uri resolveApiUri(
    String path, [
    Map<String, dynamic>? queryParameters,
  ]) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final uri = apiBaseUri.resolve(cleanPath);
    if (queryParameters == null || queryParameters.isEmpty) return uri;
    final query = <String, String>{};
    queryParameters.forEach((key, value) {
      if (value != null) query[key] = value.toString();
    });
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  static Uri _normalizeApiBaseUri(String raw) {
    final parsed = Uri.parse(raw.trim());
    if (!parsed.hasScheme || parsed.host.isEmpty) {
      throw StateError(
        '$dartDefineName must be an absolute URL, received "$raw"',
      );
    }
    final segments = parsed.pathSegments.where((segment) => segment.isNotEmpty);
    final path = '/${segments.join('/')}/';
    return parsed.replace(path: path, query: null, fragment: null);
  }
}
