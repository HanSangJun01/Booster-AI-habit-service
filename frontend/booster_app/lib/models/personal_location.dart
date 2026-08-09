import 'json.dart';

/// 백엔드 `LocationResponse` (GET/POST/PUT /api/users/me/location).
///
/// 개인 습관 인증의 기준 위치다. 이 좌표에서 [radiusMeters] 안에 있어야
/// `POST /api/personal/check-in`이 성공한다. 등록 전에는 개인 인증을 할 수
/// 없으므로, 인증 화면은 이 값이 없으면 먼저 등록을 안내해야 한다.
class PersonalLocation {
  final int? userId;
  final double lat;
  final double lng;
  final int radiusMeters;
  final String? placeName;
  final DateTime? updatedAt;

  PersonalLocation({
    this.userId,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    this.placeName,
    this.updatedAt,
  });

  factory PersonalLocation.fromJson(Map<String, dynamic> json) {
    return PersonalLocation(
      userId: asIntOrNull(json['userId']),
      lat: asDouble(json['lat']),
      lng: asDouble(json['lng']),
      radiusMeters: asInt(json['radiusMeters']),
      placeName: json['placeName'] as String?,
      updatedAt: asDateTime(json['updatedAt']),
    );
  }

  /// 장소 이름이 없으면 좌표를 대신 보여준다.
  String get displayName {
    final name = placeName;
    if (name != null && name.isNotEmpty) return name;
    return '위도 ${lat.toStringAsFixed(5)}, 경도 ${lng.toStringAsFixed(5)}';
  }
}
