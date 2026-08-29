import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../models/shop_item.dart';
import '../../models/weekly_goal.dart';
import '../../services/shop_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';

/// 상점 — 모은 코인을 쓰는 곳.
///
/// 파는 물건은 구제권 하나다. 상점 전용 API가 없어서 보유 수량·가격·잔액을
/// 전부 `GET /api/personal/weekly-goal`에서 읽고, 구매는
/// `POST /api/personal/recovery-tickets`로 나간다([ShopService]).
///
/// ## '사용' 버튼이 없다
/// 구제권은 사용자가 쓰는 물건이 아니다. 매주 월요일 채점에서 목표를 못 채운
/// 주가 있으면 서버가 무료분부터 알아서 한 장 소모한다. 사용자가 할 일은 미리
/// 사두는 것뿐이라, 버튼을 두면 앱이 하지도 않는 일을 약속하게 된다.
///
/// "사용"에 가장 가까운 동작인 **사후 구제**는 여기가 아니라 홈의 구제 안내
/// 팝업에서 일어난다(`rescue_notice.dart`).
///
/// 기프티콘은 자리만 잡아둔 외관이라 '준비 중'으로 잠겨 있다 — 재고·발급 없이
/// 팔면 코인만 빠지고 물건은 안 나온다.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  static const _shopTabIndex = 3;

  bool _loading = true;

  /// 구매가 도는 중. 두 번 눌러 두 번 사는 걸 막는다.
  bool _busy = false;

  /// 서버가 준 구제권 현황. 위치 미등록이거나 조회에 실패하면 null이다.
  WeeklyGoal? _goal;

  /// 현황을 못 읽은 이유. null이면 위치 미등록(=아직 시작 전)이다.
  String? _statusError;

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
    // MainScaffold가 탭을 IndexedStack으로 살려두기 때문에 다른 탭에서 코인이나
    // 구제권이 움직여도 이 화면의 initState는 다시 안 불린다. 상점 탭이 새로
    // 활성화될 때마다 다시 읽는다 — 구매 가능 판정이 잔액에 걸려 있어서, 낡은
    // 값을 들고 있으면 살 수 있는 걸 못 사거나 그 반대가 된다.
    final current = MainNavScope.of(context).current;
    if (_didInitialLoad &&
        current == _shopTabIndex &&
        _lastActiveTabIndex != _shopTabIndex) {
      _load();
    }
    _lastActiveTabIndex = current;
    _didInitialLoad = true;
  }

  /// 보유 수량·가격·잔액을 한 번에 읽는다. 셋 다 같은 응답에서 온다.
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final goal = await ShopService.fetchStatus();
      if (!mounted) return;
      setState(() {
        _goal = goal;
        _statusError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // 조회가 실패해도 화면은 열려야 한다. 기프티콘 구경과 새로고침은 서버
      // 없이도 되는 일이고, 여기서 로딩에 묶이면 빠져나갈 길이 없다.
      setState(() => _statusError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ───────────────────────── 구매 ─────────────────────────

  Future<void> _buy() async {
    if (_busy) return;

    final goal = _goal;
    if (goal == null) {
      showBoosterToast(context, _statusError ?? '인증 장소를 먼저 등록해주세요');
      return;
    }
    // 여기서 막는 건 헛된 요청을 줄이려는 것뿐이다. 최종 판정은 서버가 한다.
    if (Session.coinBalance < goal.ticketPrice) {
      final short = goal.ticketPrice - Session.coinBalance;
      showBoosterToast(context, '코인이 ${CoinPill.format(short)}개 부족해요');
      return;
    }
    if (!await _confirmPurchase(goal)) return;

    setState(() => _busy = true);
    try {
      final result = await ShopService.purchase(ShopCatalog.recoveryTicket);
      if (!mounted) return;
      showBoosterToast(context,
          '구제권을 구매했어요 · ${CoinPill.format(result.price)}코인');
      // 구매 응답은 총 수량만 준다. 무료/구매 구분과 가격은 현황을 다시 읽어야
      // 맞아서, 화면에 반쪽짜리 숫자를 남기지 않도록 여기서 갱신한다.
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmPurchase(WeeklyGoal goal) async {
    final after = Session.coinBalance - goal.ticketPrice;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _PurchaseSheet(
        price: goal.ticketPrice,
        lateRescuePrice: goal.lateRescuePrice,
        balanceAfter: after,
      ),
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
                          _sectionTitle('구제권 구매'),
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

  /// 내 구제권. 무료분과 구매분을 나눠 보여준다 — **소멸 규칙이 다르다.**
  /// 합쳐서 "3개"로만 보여주면 월말에 하나가 사라진 걸 사용자가 설명할 수 없다.
  Widget _pouch() {
    final goal = _goal;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('내 구제권',
                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (goal != null)
                MiniTag(
                  goal.recoveryTickets > 0 ? '${goal.recoveryTickets}개 보유' : '비어 있음',
                  bg: goal.recoveryTickets > 0 ? BC.oSoft : BC.tagBg,
                  fg: goal.recoveryTickets > 0 ? BC.oMain : const Color(0xFF86868B),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (goal == null)
            _pouchUnavailable()
          else ...[
            _ticketRow('무료', goal.freeTickets, '이번 달 말 소멸'),
            const SizedBox(height: 10),
            _ticketRow('구매', goal.paidTickets, '소멸 없음'),
            const SizedBox(height: 14),
            Container(height: 1, color: BC.line),
            const SizedBox(height: 12),
            const Text(
              '목표를 못 채운 주에 자동으로 1개 사용돼요.\n스트릭이 지켜지고 코인도 안 깎여요.',
              style: TextStyle(fontSize: 12.5, color: BC.ink2, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  /// 현황을 못 읽었을 때. 위치 미등록(에러 없음)과 조회 실패를 구분해 안내한다 —
  /// 전자는 사용자가 할 일이 있고, 후자는 다시 시도하면 되는 일이다.
  Widget _pouchUnavailable() {
    final error = _statusError;
    return Row(
      children: [
        _icon(Icons.confirmation_num_rounded, fg: BC.ink3, bg: BC.tagBg),
        const SizedBox(width: 13),
        Expanded(
          child: Text(
            error ?? '인증 장소를 등록하면 구제권을 확인할 수 있어요',
            style: const TextStyle(fontSize: 12.5, color: BC.ink3, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _ticketRow(String label, int count, String note) {
    final has = count > 0;
    return Row(
      children: [
        _icon(Icons.confirmation_num_rounded,
            fg: has ? BC.oMain : BC.ink3, bg: has ? BC.oSoft : BC.tagBg, size: 36),
        const SizedBox(width: 12),
        Text(label,
            style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: has ? BC.ink : BC.ink3)),
        const SizedBox(width: 8),
        Text('$count개',
            style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: has ? BC.oMain : BC.ink3)),
        const Spacer(),
        Text(note, style: const TextStyle(fontSize: 11.5, color: BC.ink3)),
      ],
    );
  }

  /// 구제권 판매 카드. 가격은 서버가 준 값만 쓴다.
  Widget _recoveryTicketCard() {
    const item = ShopCatalog.recoveryTicket;
    final goal = _goal;

    return ValueListenableBuilder<int>(
      valueListenable: Session.coinBalanceListenable,
      builder: (_, balance, __) {
        final price = goal?.ticketPrice;
        final buyable = price != null && !_busy;
        final affordable = price != null && balance >= price;

        return GestureDetector(
          onTap: buyable ? _buy : null,
          behavior: HitTestBehavior.opaque,
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _icon(Icons.confirmation_num_rounded,
                        fg: BC.oMain, bg: BC.oSoft, size: 46),
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
                    Text(price == null ? '—' : CoinPill.format(price),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900, color: BC.oMain)),
                    const Spacer(),
                    _PillButton(
                      label: price == null
                          ? '구매 불가'
                          : (affordable ? '구매' : '코인 부족'),
                      enabled: buyable && affordable,
                      onTap: _buy,
                    ),
                  ],
                ),
                if (goal != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '미리 사두면 ${CoinPill.format(goal.ticketPrice)}, '
                    '놓친 뒤에 사면 ${CoinPill.format(goal.lateRescuePrice)}이에요.',
                    style: const TextStyle(fontSize: 12, color: BC.ink3, height: 1.4),
                  ),
                ],
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
    final price = item.price;
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
                if (price != null) ...[
                  const CoinDot(size: 15),
                  const SizedBox(width: 5),
                  Text(CoinPill.format(price),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800, color: BC.ink3)),
                ],
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

/// 구매 확인 바텀시트. 누르기 전에 얼마가 빠지고 얼마가 남는지 보여준다.
class _PurchaseSheet extends StatelessWidget {
  final int price;
  final int lateRescuePrice;
  final int balanceAfter;

  const _PurchaseSheet({
    required this.price,
    required this.lateRescuePrice,
    required this.balanceAfter,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String, Color)>[
      ('가격', '-${CoinPill.format(price)}', BC.oMain),
      ('구매 후 잔액', CoinPill.format(balanceAfter), BC.ink),
    ];

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
            const Text('구제권 구매',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              '목표를 못 채운 주에 자동으로 쓰여요. '
              '놓친 뒤에 사면 ${CoinPill.format(lateRescuePrice)}이에요.',
              style: const TextStyle(fontSize: 13.5, color: BC.ink2, height: 1.5),
            ),
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
              label: '${CoinPill.format(price)} 코인으로 구매',
              onTap: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: BC.ink3)),
              ),
            ),
          ],
        ),
      ),
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
