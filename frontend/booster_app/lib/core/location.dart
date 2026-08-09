import 'dart:async';
import 'package:geolocator/geolocator.dart';

/// 기기 위치를 못 받았을 때 던지는 예외. `message`는 그대로 사용자에게 보여준다.
class LocationException implements Exception {
  final String message;

  /// 사용자가 "다시 묻지 않음"으로 거부해서, 앱 안에서 다시 물어볼 수 없는 상태.
  /// 이 경우엔 화면에서 앱 설정을 직접 열어주는 버튼을 띄운다.
  final bool needsAppSettings;

  LocationException(this.message, {this.needsAppSettings = false});

  @override
  String toString() => message;
}

/// 기기 GPS 좌표 획득. 인증 제출에 실어 보낼 latitude/longitude를 여기서 얻는다.
///
/// 권한 흐름은 geolocator 기준이다:
/// 위치 서비스 on 여부 → 권한 확인 → (denied면) 권한 요청 → 좌표 측정.
/// 각 단계 실패는 전부 [LocationException]으로 바꿔서, 화면은 message만 그대로
/// 보여주면 되게 한다.
class LocationService {
  /// 실내/약전계에서 무한정 매달리지 않도록 건 상한. 초과하면 재시도를 안내한다.
  static const Duration _timeLimit = Duration(seconds: 15);

  static const String _serviceOffMessage = '기기의 위치 서비스가 꺼져 있어요. 설정에서 위치를 켠 뒤 다시 시도해주세요.';

  /// 현재 좌표를 반환한다. 실패 시 [LocationException].
  static Future<Position> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationException(_serviceOffMessage);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationException(
        '위치 권한이 차단돼 있어요. 앱 설정에서 위치 권한을 허용해주세요.',
        needsAppSettings: true,
      );
    }
    if (permission == LocationPermission.denied) {
      throw LocationException('위치 권한이 필요해요. GPS 인증을 하려면 위치 접근을 허용해주세요.');
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _timeLimit,
        ),
      );
    } on TimeoutException {
      throw LocationException('위치를 확인하지 못했어요. 실외로 이동한 뒤 다시 시도해주세요.');
    } on LocationServiceDisabledException {
      throw LocationException(_serviceOffMessage);
    } on PermissionDeniedException {
      throw LocationException(
        '위치 권한이 차단돼 있어요. 앱 설정에서 위치 권한을 허용해주세요.',
        needsAppSettings: true,
      );
    }
  }

  /// 권한이 영구 거부됐을 때(=needsAppSettings) 앱 설정 화면을 연다.
  static Future<bool> openAppSettings() => Geolocator.openAppSettings();
}
