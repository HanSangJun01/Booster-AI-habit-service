import '../core/api_client.dart';
import '../core/session.dart';
import '../models/recovery.dart';

/// 복귀 미션 — 백엔드 `RecoveryController` (`/api/personal/recovery`).
///
/// 개인 체크인을 놓치면 서버가 복귀 미션을 열어둔다. 데드라인 안에 GPS 인증을
/// 다시 하면([perform]) 만회되고, 넘기면 실패로 굳는다. 어느 쪽이든 코인이
/// 차감된다(성공 -50, 실패 -100).
///
/// 미션을 앱이 만들지 않는다 — 생성은 서버 몫이고, 앱은 상태 조회와 수행만 한다.
class RecoveryService {
  /// GET /api/personal/recovery/status. 대기 중인 복귀 미션이 있는지.
  static Future<RecoveryStatus> fetchStatus() async {
    final data = ApiClient.asObject(await ApiClient.get('/personal/recovery/status'));
    return RecoveryStatus.fromJson(data);
  }

  /// POST /api/personal/recovery. 실제 기기 좌표로 복귀 미션 수행.
  static Future<RecoveryResult> perform({
    required double latitude,
    required double longitude,
  }) async {
    final data = ApiClient.asObject(await ApiClient.post('/personal/recovery', body: {
      'lat': latitude,
      'lng': longitude,
    }));
    final result = RecoveryResult.fromJson(data);
    Session.coinBalance = result.coinBalance;
    return result;
  }
}
