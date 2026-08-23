import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shop_item.dart';
import 'session.dart';

/// 보유 아이템 수량 — 기기 로컬에 남는다(SharedPreferences).
///
/// 백엔드에 인벤토리 API가 없어서 서버는 누가 뭘 가졌는지 모른다. 그래서
/// 보유분은 이 기기에만 있다 — 앱을 지우거나 기기를 바꾸면 함께 사라지고,
/// 다른 기기에서 로그인해도 따라오지 않는다. 인벤토리 API가 생기면 이 클래스의
/// 저장소만 서버로 갈아끼우면 되고, 화면·서비스는 그대로 둘 수 있다.
///
/// 키에 userId를 넣는 이유: 저장소는 계정이 아니라 **기기** 단위다. 한 기기에서
/// 계정을 바꿔 로그인하면 앞사람 보유분이 그대로 보인다.
///
/// [Session.coinBalanceListenable]과 같은 이유로 [countsListenable]을 쓴다 —
/// 화면 위젯이 const라 다시 빌드될 이유가 없어도 수량이 바뀌면 갱신되도록.
class Inventory {
  static const _prefix = 'inventory';

  /// {상품 id: 보유 수량}. 아직 불러오지 않았으면 비어 있다.
  static final ValueNotifier<Map<String, int>> countsListenable =
      ValueNotifier<Map<String, int>>(const {});

  static Map<String, int> get counts => countsListenable.value;

  static int countOf(String itemId) => counts[itemId] ?? 0;

  static String _key(int userId, String itemId) => '$_prefix.$userId.$itemId';

  /// 저장소에서 보유 수량을 읽어 메모리에 채운다.
  ///
  /// 로그인 전(userId 없음)이면 빈 값으로 둔다. 화면이 열릴 때마다 부르면 되고,
  /// 여러 번 불러도 문제없다.
  static Future<void> load({
    Iterable<ShopItem> items = ShopCatalog.ownable,
  }) async {
    final userId = Session.userId;
    if (userId == null) {
      countsListenable.value = const {};
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    countsListenable.value = {
      for (final item in items) item.id: prefs.getInt(_key(userId, item.id)) ?? 0,
    };
  }

  /// 보유 수량을 [delta]만큼 움직이고 저장한다. 0 아래로는 내려가지 않는다.
  /// 반환값은 반영된 후의 수량.
  static Future<int> _move(String itemId, int delta) async {
    final userId = Session.userId;
    if (userId == null) return 0;

    final prefs = await SharedPreferences.getInstance();
    // 메모리 값이 아니라 저장소 값을 기준으로 계산한다. load()를 건너뛰고
    // 바로 구매하는 경로에서도 어긋나지 않게.
    final current = prefs.getInt(_key(userId, itemId)) ?? 0;
    final next = current + delta < 0 ? 0 : current + delta;
    await prefs.setInt(_key(userId, itemId), next);

    countsListenable.value = {...counts, itemId: next};
    return next;
  }

  static Future<int> add(String itemId, {int count = 1}) => _move(itemId, count);

  /// 한 개 쓴다. 보유분이 없으면 아무것도 하지 않고 false.
  static Future<bool> consume(String itemId) async {
    final userId = Session.userId;
    if (userId == null) return false;

    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_key(userId, itemId)) ?? 0;
    if (current <= 0) {
      // 메모리 값이 저장소와 어긋나 있었다면 여기서 바로잡는다.
      countsListenable.value = {...counts, itemId: 0};
      return false;
    }
    await _move(itemId, -1);
    return true;
  }

  /// 로그아웃 시 메모리만 비운다.
  ///
  /// 저장소는 건드리지 않는다 — 같은 계정으로 다시 로그인하면 보유분이 그대로
  /// 돌아와야 한다. 지워야 할 건 "지금 화면에 떠 있는 남의 수량"뿐이다.
  static void clear() => countsListenable.value = const {};
}
