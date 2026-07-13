/// Extracts records from a BoltFox paginated response payload.
///
/// The backend currently uses `pageData`, while some endpoints and older
/// responses use one of the other supported field names. Direct list payloads
/// are supported as well.
List<Map<String, dynamic>> extractApiRows(dynamic data) {
  dynamic rows = data;
  if (data is Map) {
    rows =
        data['pageData'] ??
        data['list'] ??
        data['rows'] ??
        data['records'] ??
        data['data'] ??
        data['items'];
  }
  if (rows is! List) {
    return const [];
  }
  return rows
      .whereType<Map>()
      .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
      .toList();
}
