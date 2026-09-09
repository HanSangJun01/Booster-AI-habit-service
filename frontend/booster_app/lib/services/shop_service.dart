import '../core/api_client.dart';
import '../core/session.dart';
import '../models/shop_item.dart';
import '../models/weekly_goal.dart';
import 'personal_service.dart';

/// 상점 — 파는 물건은 구제권 하나뿐이고, **전용 API는 없다.**
///
/// 상품·주문 테이블을 만들지 않기로 한 결정에 따른 것이다(계획서 §A-6). 구제권은
/// 이미 A축 도메인 API를 가지고 있어서 상점은 그걸 그대로 부른다:
///
///     구매        POST /api/personal/recovery-tickets
///     보유·가격    GET  /api/personal/weekly-goal
///
/// ## 코인을 직접 움직이지 않는다
/// 예전엔 `POST /api/users/me/coins`로 잔액을 깎고 보유 수량은 기기에 남겼다.
/// 그 경로는 **서버에 없고 앞으로도 안 생긴다** — 클라이언트가 잔액을 임의로
/// 조작할 수 있게 되기 때문이다. 코인은 서버 이벤트로만 움직인다.
///
/// 그래서 가격도 보유 수량도 이제 서버가 단일 진실 원천이다. 앱은 어떤 물건이
/// 있는지([ShopCatalog])와 그걸 어떻게 보여줄지만 안다.
class ShopService {
  static const _ticketPath = '/personal/recovery-tickets';

  /// 상점이 그릴 현황(보유 수량·가격·잔액). 위치 미등록이면 null이다.
  ///
  /// 구제권 조회 창구가 주간 목표 응답이라 그대로 넘겨받는다. 상점만 쓰는
  /// 값이 아니어서 호출은 [PersonalService]에 두고 여기선 이름만 빌려준다.
  static Future<WeeklyGoal?> fetchStatus() => PersonalService.fetchWeeklyGoal();

  /// 구제권을 산다. 성공하면 갱신된 보유 수량·잔액이 돌아온다.
  ///
  /// 잔액 판정은 **서버가 최종**이다. 앱은 버튼을 흐리게 하는 정도로만 미리
  /// 걸러낸다 — 표시 가격이 낡았거나 다른 기기에서 코인을 썼을 수 있어서,
  /// 앱 판정을 최종으로 삼으면 살 수 있는 걸 못 사거나 그 반대가 된다.
  /// 부족하면 서버가 400을 주고, 그때 코인은 차감되지 않는다.
  static Future<RecoveryTicketPurchase> purchase(ShopItem item) async {
    if (item.kind != ShopItemKind.recoveryTicket || !item.purchasable) {
      throw ApiException('아직 판매하지 않는 상품이에요');
    }

    // 요청 본문이 없다. 무엇을 사는지는 경로가 말해준다.
    final data = ApiClient.asObject(await ApiClient.post(_ticketPath));
    final result = RecoveryTicketPurchase.fromJson(data);
    Session.coinBalance = result.coinBalance;
    return result;
  }
}
