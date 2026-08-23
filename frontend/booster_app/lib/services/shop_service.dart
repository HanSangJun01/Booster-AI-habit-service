import '../core/api_client.dart';
import '../core/inventory.dart';
import '../core/session.dart';
import '../models/json.dart';
import '../models/shop_item.dart';

/// 상점 구매/사용 — 서버로 나가는 건 **가격뿐**이다.
///
/// 어떤 물건인지는 앱만 안다([ShopCatalog]). 서버에는 잔액을 얼마나 움직일지만
/// 알리고, 보유 수량은 기기에 남긴다([Inventory]).
///
/// ## 아직 백엔드에 없는 엔드포인트다
/// `integration/a-b-axis` 기준 코인을 직접 증감하는 API가 없다 — 코인은 체크인·
/// 복귀·정산 같은 서버 이벤트로만 움직이고, `CoinTransactionReason`에도 구매
/// 항목이 없다. 그래서 아래 규약으로 호출해두되, 서버가 "그런 경로 없다"고
/// 답하면([_isMissingEndpoint]) 로컬 잔액만 조정해서 화면이 멈추지 않게 한다.
///
///     POST /api/users/me/coins   { "amount": -100 }
///     → { "coinBalance": 400 }
///
/// 엔드포인트가 생기면 [_isMissingEndpoint] 분기만 지우면 된다. 그 전까지는
/// 로컬 폴백이 걸린 상태이므로, 이 앱에서 산 물건은 서버 코인 내역에 남지
/// 않는다는 점을 감안해야 한다.
class ShopService {
  static const _coinPath = '/users/me/coins';

  /// 구매. 성공하면 갱신된 잔액을 돌려준다.
  ///
  /// 잔액 확인을 서버가 아니라 앱이 한다 — 폴백 경로에서는 서버가 막아줄 수
  /// 없기 때문이다. 엔드포인트가 생기면 서버도 같은 판정을 해야 한다.
  static Future<int> purchase(ShopItem item) async {
    if (!item.purchasable) {
      throw ApiException('아직 판매하지 않는 상품이에요');
    }
    if (Session.coinBalance < item.price) {
      throw ApiException('코인이 부족해요');
    }

    // 물건을 먼저 넣고 코인을 뺀다. 실패는 대부분 네트워크에서 나는데, 순서가
    // 반대면 코인만 빠지고 물건이 안 들어오는 쪽으로 어긋난다.
    await Inventory.add(item.id);
    try {
      return await _moveCoins(-item.price);
    } catch (_) {
      await Inventory.consume(item.id);
      rethrow;
    }
  }

  /// 보유분 하나를 사용한다. 성공하면 갱신된 잔액을 돌려준다.
  ///
  /// 구제권의 "면제"가 여기서 일어난다 — 서버가 복귀 미션에서 이미 가져간
  /// 코인을 [ShopItem.refundAmount]만큼 되돌려주는 방식이다. 서버가 미션을
  /// 어떻게 처리했는지는 앱이 되돌릴 수 없어서, 되돌릴 수 있는 코인만 되돌린다.
  static Future<int> use(ShopItem item) async {
    if (!item.ownable) {
      throw ApiException('사용할 수 있는 상품이 아니에요');
    }
    if (!await Inventory.consume(item.id)) {
      throw ApiException('보유한 ${item.name}이 없어요');
    }
    try {
      return await _moveCoins(item.refundAmount);
    } catch (_) {
      await Inventory.add(item.id);
      rethrow;
    }
  }

  /// 잔액을 [amount]만큼 움직인다(음수면 차감). 갱신된 잔액을 돌려준다.
  static Future<int> _moveCoins(int amount) async {
    if (amount == 0) return Session.coinBalance;

    int balance;
    try {
      final raw = await ApiClient.post(_coinPath, body: {'amount': amount});
      // 서버가 잔액을 안 줄 수도 있다(204 등). 요청 자체는 통했으므로 앱이
      // 계산한 값으로 이어간다 — 여기서 예외를 던지면 코인은 빠졌는데 화면은
      // 실패로 보이는 최악의 조합이 된다.
      final data = raw is Map<String, dynamic> ? raw : const <String, dynamic>{};
      balance = data['coinBalance'] == null
          ? Session.coinBalance + amount
          : asInt(data['coinBalance']);
    } on ApiException catch (e) {
      if (!_isMissingEndpoint(e)) rethrow;
      balance = Session.coinBalance + amount;
    }

    Session.coinBalance = balance < 0 ? 0 : balance;
    return Session.coinBalance;
  }

  /// "엔드포인트가 아직 없다"로 읽을 응답인지.
  ///
  /// 연결 실패(statusCode == null)나 4xx 업무 오류는 여기 해당하지 않는다 —
  /// 그건 진짜 실패라서 사용자에게 그대로 알려야 한다.
  static bool _isMissingEndpoint(ApiException e) =>
      e.statusCode == 404 || e.statusCode == 405 || e.statusCode == 501;
}
