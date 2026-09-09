/// 상점 상품 — 서버가 아니라 **앱이** 들고 있는 카탈로그.
///
/// 백엔드에 상품 테이블이 없다. 파는 물건이 구제권 하나뿐이라 상점 전용 API를
/// 만들지 않기로 했고(계획서 §A-6), 구매는 이미 있던 도메인 API
/// (`POST /api/personal/recovery-tickets`)를 그대로 쓴다.
///
/// 그래서 이 파일이 아는 건 **무엇을 파는지**까지다. 얼마에 파는지와 몇 개를
/// 가지고 있는지는 서버가 정한다(`GET /api/personal/weekly-goal`).
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

  /// 앱이 아는 표시가.
  ///
  /// **null이면 서버가 정하는 가격이다**(구제권 →
  /// `GET /api/personal/weekly-goal`의 `ticketPrice`). 여기 숫자를 박아두면
  /// 서버가 값을 바꿨을 때 "표시는 800인데 결제는 1,000"이 된다.
  ///
  /// 기프티콘은 아직 팔지 않아서 서버에 가격이 없다. 그건 교환 시세를 보여주는
  /// 용도로 앱이 들고 있다.
  final int? price;

  /// 지금 살 수 있는 상품인지. 기프티콘은 false다.
  final bool purchasable;

  const ShopItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.summary,
    this.price,
    this.purchasable = false,
  });
}

/// 판매 목록.
class ShopCatalog {
  /// 구제권. 단품 한 종류다.
  ///
  /// 사서 보관해두는 것까지가 앱의 몫이다. 쓰는 시점은 사용자가 고르지 않는다 —
  /// 매주 월요일 채점에서 목표를 못 채운 주가 있으면 서버가 무료분부터 알아서
  /// 한 장 소모한다. 그래서 '사용' 버튼이 없다.
  ///
  /// 가격을 비워둔 건 서버가 [price]의 주인이기 때문이다.
  static const recoveryTicket = ShopItem(
    id: 'recovery_ticket',
    kind: ShopItemKind.recoveryTicket,
    name: '구제권',
    summary: '목표를 못 채운 주에 스트릭을 지켜줘요',
    purchasable: true,
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

  static const all = <ShopItem>[recoveryTicket, ...gifticons];
}
