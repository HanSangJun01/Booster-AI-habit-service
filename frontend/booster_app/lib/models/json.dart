/// 백엔드 JSON을 Dart 값으로 옮길 때 쓰는 공통 변환기.
///
/// 숫자 필드는 서버가 Java `long`/`int`/`BigDecimal` 중 무엇으로 내보냈는지에
/// 따라 JSON에서 int로도 double로도 올 수 있어서(예: `participationRate`가
/// 0이면 `0`, 0.5면 `0.5`), 한쪽으로만 캐스팅하면 런타임에 깨진다.
library;

int asInt(dynamic v, {int fallback = 0}) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

int? asIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double asDouble(dynamic v, {double fallback = 0}) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

bool asBool(dynamic v, {bool fallback = false}) => v is bool ? v : fallback;

String asString(dynamic v, {String fallback = ''}) => v is String ? v : fallback;

/// `LocalDate`("2026-07-28") / `LocalDateTime` / `OffsetDateTime` 문자열을
/// DateTime으로 읽는다. 파싱 실패나 null은 null로 돌려준다.
DateTime? asDateTime(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v);
}

/// 날짜만 비교할 때 쓰는 정규화(시/분/초 제거).
DateTime? asDateOnly(dynamic v) {
  final parsed = asDateTime(v);
  return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
}

List<Map<String, dynamic>> asObjectList(dynamic v) {
  if (v is! List) return const [];
  return v.whereType<Map<String, dynamic>>().toList();
}
