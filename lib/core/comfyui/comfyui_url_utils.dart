/// Normalizes a ComfyUI server base URL for HTTP and WebSocket clients.
///
/// Users often paste `http://127.0.0.1:8188/`. Keeping the trailing slash makes
/// later endpoint joins produce paths like `//ws`, which ComfyUI may reject.
String normalizeComfyUIBaseUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return trimmed;

  final schemeSeparatorIndex = trimmed.indexOf('://');
  final minLength = schemeSeparatorIndex == -1 ? 0 : schemeSeparatorIndex + 3;

  var end = trimmed.length;
  while (end > minLength && trimmed.codeUnitAt(end - 1) == 0x2f) {
    end--;
  }
  return trimmed.substring(0, end);
}

/// Builds the ComfyUI `/ws` URI from a normalized or user-provided base URL.
Uri buildComfyUIWebSocketUri({
  required String baseUrl,
  required String clientId,
}) {
  final wsBaseUrl = normalizeComfyUIBaseUrl(baseUrl)
      .replaceFirst(RegExp(r'^http://', caseSensitive: false), 'ws://')
      .replaceFirst(RegExp(r'^https://', caseSensitive: false), 'wss://');
  final baseUri = Uri.parse(wsBaseUrl);
  final normalizedPath = baseUri.path.replaceFirst(RegExp(r'/+$'), '');
  final wsPath = normalizedPath.isEmpty ? '/ws' : '$normalizedPath/ws';

  return Uri(
    scheme: baseUri.scheme,
    userInfo: baseUri.userInfo,
    host: baseUri.host,
    port: baseUri.hasPort ? baseUri.port : null,
    path: wsPath,
    queryParameters: {'clientId': clientId},
  );
}
