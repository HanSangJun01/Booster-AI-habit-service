/// 상점 상품 — 서버가 아니라 **앱이** 들고 있는 카탈로그.
///
/// 백엔드에는 상품 테이블도 구매 엔드포인트도 없다. 그래서 무엇을 파는지는
/// 앱이 정하고, 서버에는 "잔액을 얼마나 움직일지"(가격)만 알린다. 어떤 물건을
/// 샀는지는 보내지 않는다 — 서버가 알 필요가 없고, 알아도 기록할 자리가 없다
/// (`CoinTransactionReason`에 구매 항목이 없다).
///
/// 이 파일이 Flutter를 import하지 않는 건 다른 모델들과 같은 이유다. 색·아이콘
/// 같은 겉모습은 화면(`shop_screen.dart`)이 [ShopItemKind]를 보고 정한다.
library;

enum ShopItemKind {
  /// 구제권 — MVP에서 실제로 동작하는 유일한 상품.
  recoveryTicket,

  /// 기프티콘 — 이번 범위에서는 외관만. 살 수 없다.
  gifticon,
}

class ShopItem {
  final String id;
  final ShopItemKind kind;
  final String name;

  /// 카드에 한 줄로 붙는 설명.
  final String summary;

  /// 구매가(코인).
  final int price;

  /// 사용했을 때 돌려받는 코인.
  ///
  /// 구제권이 하는 일이 이것이다. 복귀 미션을 수행하면 서버가 코인을 차감하는데
  /// (성공 -50, 실패 -100) 그 차감 자체는 앱이 막을 수 없다. 그래서 "면제"를
  /// 차감분을 되돌려주는 방식으로 구현한다.
  final int refundAmount;

  /// 지금 살 수 있는 상품인지. 기프티콘은 false다.
  final bool purchasable;

  /// 사서 보관해뒀다가 나중에 쓰는 상품인지.
  final bool ownable;

  const ShopItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.summary,
    required this.price,
    this.refundAmount = 0,
    this.purchasable = false,
    this.ownable = false,
  });
}

/// 판매 목록.
///
/// 가격을 바꾸려면 여기 숫자만 고치면 된다 — 화면도 서비스도 값을 따로 들고
/// 있지 않다.
class ShopCatalog {
  /// 구제권. 단품 한 종류다.
  static const recoveryTicket = ShopItem(
    id: 'recovery_ticket',
    kind: ShopItemKind.recoveryTicket,
    name: '구제권',
    summary: '복귀 미션으로 빠져나간 코인을 되돌려받아요',
    price: 100,
    refundAmount: 100,
    purchasable: true,
    ownable: true,
  );

  /// 기프티콘 — 외관만 있는 자리. 눌러도 구매로 이어지지 않는다.
  ///
  /// 실제로 팔려면 재고·발급·정산이 붙어야 해서 백엔드 없이는 흉내조차 위험하다
  /// (코인만 빠지고 물건은 안 나온다). 그래서 [purchasable]을 false로 두고
  /// 화면이 '준비 중'으로 잠근다.
  static const gifticons = <ShopItem>[
    ShopItem(
      id: 'gifticon_americano',
      kind: ShopItemKind.gifticon,
      name: '아메리카노',
      summary: '카페 기프티콘',
      price: 4500,
    ),
    ShopItem(
      id: 'gifticon_convenience',
      kind: ShopItemKind.gifticon,
      name: '편의점 5천원권',
      summary: '편의점 모바일 금액권',
      price: 5000,
    ),
    ShopItem(
      id: 'gifticon_movie',
      kind: ShopItemKind.gifticon,
      name: '영화 관람권',
      summary: '2D 일반 상영 1인',
      price: 12000,
    ),
    ShopItem(
      id: 'gifticon_chicken',
      kind: ShopItemKind.gifticon,
      name: '치킨 세트',
      summary: '후라이드 + 콜라 1.25L',
      price: 20000,
    ),
  ];

  /// 보유 수량을 읽어와야 하는 상품들.
  static const ownable = <ShopItem>[recoveryTicket];

  static const all = <ShopItem>[recoveryTicket, ...gifticons];

  static ShopItem? byId(String id) {
    for (final item in all) {
      if (item.id == id) return item;
    }
    return null;
  }
}
