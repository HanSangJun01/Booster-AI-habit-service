import 'json.dart';

/// 백엔드 `LocationResponse` (GET/POST/PUT /api/users/me/location).
///
/// 개인 습관 인증의 기준 위치다. 이 좌표에서 [radiusMeters] 안에 있어야
/// `POST /api/personal/check-in`이 성공한다. 등록 전에는 개인 인증을 할 수
/// 없으므로, 인증 화면은 이 값이 없으면 먼저 등록을 안내해야 한다.
///
/// ## 변경은 다음 달 1일부터다
/// [lat]/[lng]/[radiusMeters]는 **지금 인증에 쓰이는** 값이고, `pending*`은
/// 예약된 값이다. 수정(PUT)해도 즉시 바뀌지 않는다 — 인증 직전에 지금 있는
/// 자리로 장소를 옮기면 어디서든 통과할 수 있어서, 주간 목표와 같은 주기로
/// 묶었다. 화면은 둘을 함께 보여줘야 한다. 안 그러면 사용자가 "바꿨는데 왜
/// 그대로지?" 하고 계속 다시 누른다.
class PersonalLocation {
  /// 반경 하한. 휴대폰 GPS 오차(10~50m)보다 좁으면 제자리에서도 인증이 실패한다.
  static const int minRadiusMeters = 10;

  /// 반경 상한. 예전엔 상한이 없어 서울에 등록하고 시드니에서 인증할 수 있었다.
  static const int maxRadiusMeters = 1000;

  final int? userId;
  final double lat;
  final double lng;
  final int radiusMeters;
  final String? placeName;

  /// 다음 달 1일부터 적용될 예약 값. 예약이 없으면 전부 null이다.
  final double? pendingLat;
  final double? pendingLng;
  final int? pendingRadiusMeters;
  final String? pendingPlaceName;

  final DateTime? updatedAt;

  PersonalLocation({
    this.userId,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    this.placeName,
    this.pendingLat,
    this.pendingLng,
    this.pendingRadiusMeters,
    this.updatedAt,
    this.pendingPlaceName,
  });

  factory PersonalLocation.fromJson(Map<String, dynamic> json) {
    return PersonalLocation(
      userId: asIntOrNull(json['userId']),
      lat: asDouble(json['lat']),
      lng: asDouble(json['lng']),
      radiusMeters: asInt(json['radiusMeters']),
      placeName: json['placeName'] as String?,
      pendingLat: json['pendingLat'] == null ? null : asDouble(json['pendingLat']),
      pendingLng: json['pendingLng'] == null ? null : asDouble(json['pendingLng']),
      pendingRadiusMeters: asIntOrNull(json['pendingRadiusMeters']),
      pendingPlaceName: json['pendingPlaceName'] as String?,
      updatedAt: asDateTime(json['updatedAt']),
    );
  }

  /// 변경이 예약돼 있는가. 셋은 한 벌로 오거나 한 벌로 비어 있다.
  bool get hasPendingChange =>
      pendingLat != null && pendingLng != null && pendingRadiusMeters != null;

  /// 장소 이름이 없으면 좌표를 대신 보여준다.
  String get displayName => _nameOf(placeName, lat, lng);

  /// 예약된 장소의 표시 이름. 예약이 없으면 null이다.
  String? get pendingDisplayName => hasPendingChange
      ? _nameOf(pendingPlaceName, pendingLat!, pendingLng!)
      : null;

  static String _nameOf(String? name, double lat, double lng) {
    if (name != null && name.isNotEmpty) return name;
    return '위도 ${lat.toStringAsFixed(5)}, 경도 ${lng.toStringAsFixed(5)}';
  }
}
