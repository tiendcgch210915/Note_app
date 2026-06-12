List<String> parseChecklistStepLines(String raw) {
  return raw
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map(_normalizeStepLine)
      .where((line) => line.isNotEmpty)
      .toList();
}

String _normalizeStepLine(String line) {
  var text = line.trim();
  text = text.replaceFirst(RegExp(r'^#+\s*'), '');
  text = text.replaceFirst(RegExp(r'^(?:[-*•‣◦▪▫–—]\s*)?(?:\[[ xX]\]\s*)'), '');
  text = text.replaceFirst(
    RegExp(r'^(?:[-*•‣◦▪▫–—]+|\d+[\.)]|[a-zA-Z][\.)])\s+'),
    '',
  );
  return text.trim();
}
