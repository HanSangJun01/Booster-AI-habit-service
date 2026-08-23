import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/inventory.dart';
import '../../core/session.dart';
import '../../models/shop_item.dart';
import '../../services/shop_service.dart';
import '../../services/user_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';

/// 상점 — 모은 코인을 쓰는 곳.
///
/// 서버에 상점이 없다. 파는 물건은 앱이 들고 있고([ShopCatalog]), 보유 수량은
/// 기기에 남으며([Inventory]), 서버로는 가격만 나간다([ShopService]).
///
/// 이번 범위에서 실제로 도는 건 구제권 하나다. 기프티콘은 자리만 잡아둔
/// 외관이라 '준비 중'으로 잠겨 있다 — 재고·발급 없이 팔면 코인만 빠지고 물건은
/// 안 나온다.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  static const _shopTabIndex = 3;

  bool _loading = true;

  /// 구매·사용이 도는 중. 두 번 눌러 두 번 사는 걸 막는다.
  bool _busy = false;

  bool _didInitialLoad = false;
  int? _lastActiveTabIndex;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MainScaffold가 탭을 IndexedStack으로 살려두기 때문에 다른 탭에서 코인이
    // 움직여도 이 화면의 initState는 다시 안 불린다. 상점 탭이 새로 활성화될
    // 때마다 잔액을 다시 본다 — 구매 가능 판정이 잔액에 걸려 있어서, 낡은 값을
    // 들고 있으면 살 수 있는 걸 못 사거나 그 반대가 된다.
    final current = MainNavScope.of(context).current;
    if (_didInitialLoad &&
        current == _shopTabIndex &&
        _lastActiveTabIndex != _shopTabIndex) {
      _load();
    }
    _lastActiveTabIndex = current;
    _didInitialLoad = true;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 보유 수량은 기기에서, 잔액은 서버에서. 서로 의존하지 않는다.
      await Future.wait([Inventory.load(), _refreshBalance()]);
    } finally {
      // 잔액 조회가 실패해도 화면은 열려야 한다. 보유분 확인과 사용은 서버 없이도
      // 되는 일이고, 여기서 로딩에 묶이면 빠져나갈 길이 없다.
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 잔액만 다시 읽는다. 실패는 삼킨다 — 화면을 막을 만한 일이 아니다.
  Future<void> _refreshBalance() async {
    try {
      await UserService.fetchMe();
    } on ApiException {
      // Session에 남아 있는 마지막 잔액으로 계속 간다.
    }
  }

  // ───────────────────────── 구매 / 사용 ─────────────────────────

  Future<void> _buy(ShopItem item) async {
    if (_busy) return;

    if (!item.purchasable) {
      showBoosterToast(context, '${item.name}은 아직 준비 중이에요');
      return;
    }
    if (Session.coinBalance < item.price) {
      showBoosterToast(context, '코인이 ${CoinPill.format(item.price - Session.coinBalance)}개 부족해요');
      return;
    }
    if (!await _confirmPurchase(item)) return;

    setState(() => _busy = true);
    try {
      await ShopService.purchase(item);
      if (!mounted) return;
      showBoosterToast(context, '${item.name}을 구매했어요');
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _use(ShopItem item) async {
    if (_busy) return;
    if (Inventory.countOf(item.id) <= 0) {
      showBoosterToast(context, '보유한 ${item.name}이 없어요');
      return;
    }
    if (!await _confirmUse(item)) return;

    setState(() => _busy = true);
    try {
      await ShopService.use(item);
      if (!mounted) return;
      showBoosterToast(
          context, '${item.name}을 사용했어요 · 코인 ${CoinPill.format(item.refundAmount)} 반환');
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmPurchase(ShopItem item) async {
    final after = Session.coinBalance - item.price;
    return _confirmSheet(
      title: '${item.name} 구매',
      message: item.summary,
      rows: [
        ('가격', '-${CoinPill.format(item.price)}', BC.oMain),
        ('구매 후 잔액', CoinPill.format(after), BC.ink),
      ],
      actionLabel: '${CoinPill.format(item.price)} 코인으로 구매',
    );
  }

  Future<bool> _confirmUse(ShopItem item) async {
    final after = Session.coinBalance + item.refundAmount;
    return _confirmSheet(
      title: '${item.name} 사용',
      message: '복귀 미션으로 빠져나간 코인 ${CoinPill.format(item.refundAmount)}개를 돌려받아요.\n'
          '한 번 쓰면 되돌릴 수 없어요.',
      rows: [
        ('반환', '+${CoinPill.format(item.refundAmount)}', BC.green),
        ('사용 후 잔액', CoinPill.format(after), BC.ink),
      ],
      actionLabel: '사용하기',
    );
  }

  Future<bool> _confirmSheet({
    required String title,
    required String message,
    required List<(String, String, Color)> rows,
    required String actionLabel,
  }) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: BC.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(title,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(message,
                    style: const TextStyle(fontSize: 13.5, color: BC.ink2, height: 1.5)),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: BC.bg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(rows[i].$1,
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: BC.ink2)),
                            const Spacer(),
                            const CoinDot(size: 15),
                            const SizedBox(width: 5),
                            Text(rows[i].$2,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: rows[i].$3)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                PrimaryButton(
                  label: actionLabel,
                  onTap: () => Navigator.of(sheetContext).pop(true),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: const Text('취소',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: BC.ink3)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return confirmed ?? false;
  }

  // ───────────────────────── 화면 ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const BoosterHeader(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: BC.oMain))
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: BC.oMain,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        children: [
                          _pouch(),
                          const SizedBox(height: 22),
                          _sectionTitle('구제권'),
                          const SizedBox(height: 10),
                          _recoveryTicketCard(),
                          const SizedBox(height: 22),
                          _sectionTitle('기프티콘', tag: '준비 중'),
                          const SizedBox(height: 10),
                          _gifticonGrid(),
                        ],
                      ),
                    ),
            ),
            const BoosterBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text, {String? tag}) {
    return Row(
      children: [
        Text(text, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
        if (tag != null) ...[
          const SizedBox(width: 8),
          MiniTag(tag),
        ],
      ],
    );
  }

  /// 내 보유함. 보유 수량은 기기 저장소에서 오고, 바뀌면 여기만 다시 그린다.
  Widget _pouch() {
    const item = ShopCatalog.recoveryTicket;
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: Inventory.countsListenable,
      builder: (_, counts, __) {
        final count = counts[item.id] ?? 0;
        final has = count > 0;
        return AppCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('내 보유함',
                      style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  MiniTag(has ? '$count개 보유' : '비어 있음',
                      bg: has ? BC.oSoft : BC.tagBg,
                      fg: has ? BC.oMain : const Color(0xFF86868B)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _icon(Icons.confirmation_num_rounded,
                      fg: has ? BC.oMain : BC.ink3, bg: has ? BC.oSoft : BC.tagBg),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name,
                            style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: has ? BC.ink : BC.ink3)),
                        const SizedBox(height: 2),
                        Text(
                          has
                              ? '복귀 미션으로 코인이 빠졌을 때 사용하세요'
                              : '아직 없어요. 아래에서 구매할 수 있어요',
                          style: const TextStyle(fontSize: 12.5, color: BC.ink3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _PillButton(
                    label: '사용',
                    enabled: has && !_busy,
                    onTap: () => _use(item),
                  ),
                ],
              ),
              if (has) ...[
                const SizedBox(height: 14),
                NoteBox(
                  icon: Icons.info_outline_rounded,
                  child: Text(
                    '사용하면 코인 ${CoinPill.format(item.refundAmount)}개를 즉시 돌려받아요.',
                    style: const TextStyle(
                        fontSize: 12.5, color: BC.ink2, height: 1.45),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 구제권 판매 카드. 카드 전체가 눌린다.
  Widget _recoveryTicketCard() {
    const item = ShopCatalog.recoveryTicket;
    return ValueListenableBuilder<int>(
      valueListenable: Session.coinBalanceListenable,
      builder: (_, balance, __) {
        final affordable = balance >= item.price;
        return GestureDetector(
          onTap: _busy ? null : () => _buy(item),
          behavior: HitTestBehavior.opaque,
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _icon(Icons.confirmation_num_rounded, fg: BC.oMain, bg: BC.oSoft, size: 46),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: const TextStyle(
                                  fontSize: 16.5, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 3),
                          Text(item.summary,
                              style: const TextStyle(
                                  fontSize: 12.5, color: BC.ink2, height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const CoinDot(size: 20),
                    const SizedBox(width: 6),
                    Text(CoinPill.format(item.price),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900, color: BC.oMain)),
                    const Spacer(),
                    _PillButton(
                      label: affordable ? '구매' : '코인 부족',
                      enabled: affordable && !_busy,
                      onTap: () => _buy(item),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 기프티콘 — 외관만. 눌러도 구매로 가지 않는다.
  Widget _gifticonGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.92,
      children: [
        for (final item in ShopCatalog.gifticons) _gifticonCard(item),
      ],
    );
  }

  Widget _gifticonCard(ShopItem item) {
    return GestureDetector(
      onTap: () => showBoosterToast(context, '기프티콘 교환은 준비 중이에요'),
      behavior: HitTestBehavior.opaque,
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: BC.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.card_giftcard_rounded, size: 34, color: BC.ink3),
              ),
            ),
            const SizedBox(height: 11),
            Text(item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w700, color: BC.ink2)),
            const SizedBox(height: 2),
            Text(item.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: BC.ink3)),
            const SizedBox(height: 9),
            Row(
              children: [
                const CoinDot(size: 15),
                const SizedBox(width: 5),
                Text(CoinPill.format(item.price),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: BC.ink3)),
                const Spacer(),
                const MiniTag('준비 중'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _icon(IconData icon, {required Color fg, required Color bg, double size = 40}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(icon, size: size * 0.5, color: fg),
    );
  }
}

/// 카드 안에 들어가는 작은 주황 버튼.
class _PillButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _PillButton({required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          gradient: enabled ? BC.grad : null,
          color: enabled ? null : const Color(0xFFE7E6E3),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: enabled ? Colors.white : BC.ink3,
          ),
        ),
      ),
    );
  }
}
