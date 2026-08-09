import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../models/challenge.dart';
import '../../services/challenge_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import 'team_waiting_screen.dart';

/// 챌린지 생성 — `POST /api/challenges` (`CreateChallengeRequest`).
///
/// 예전의 "팀 만들기"가 이것이다. 백엔드에는 팀 생성 API가 없고, 팀은 챌린지에
/// 사람이 모이면 서버가 편성한다.
///
/// 서버가 검증하는 값: durationDays >= 1, depositCoins >= 0,
/// maxParticipants 2~10, title 200자 이내, category/verificationType/
/// visibility/approvalType 필수.
class TeamCreateScreen extends StatefulWidget {
  const TeamCreateScreen({super.key});
  @override
  State<TeamCreateScreen> createState() => _TeamCreateScreenState();
}

class _TeamCreateScreenState extends State<TeamCreateScreen> {
  int step = 0; // 0 기본, 1 공개설정

  /// 서버는 category를 자유 문자열로 받는다. 자주 쓸 값만 골라 둔다.
  static const _categories = ['운동', '공부', '독서', '기상'];
  int _categoryIndex = 0;

  static const _durations = [7, 14, 21, 30];
  int _durationIndex = 1;

  /// 정원. 서버 제약이 2~10이라 그 안에서 고른다.
  static const _capacities = [4, 6, 8, 10];
  int _capacityIndex = 3;

  bool isPublic = true;

  /// 참가 승인 방식. AUTO면 신청 즉시 확정, LEADER면 방장이 승인해야 한다.
  bool _leaderApproval = false;

  bool _creating = false;

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _depositCtrl = TextEditingController(text: '300');

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _depositCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        child: Column(
          children: [
            BackAppBar(
              title: step == 0 ? '챌린지 만들기' : '공개 설정',
              trailing: const CoinPill(),
            ),
            _stepDots(),
            Expanded(child: step == 0 ? _basic() : _visibility()),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
              child: step == 0
                  ? PrimaryButton(
                      label: '다음',
                      trailingIcon: Icons.chevron_right_rounded,
                      onTap: () {
                        if (_titleCtrl.text.trim().isEmpty) {
                          showBoosterToast(context, '챌린지 제목을 입력해주세요');
                          return;
                        }
                        setState(() => step = 1);
                      })
                  : PrimaryButton(
                      label: _creating ? '만드는 중...' : '챌린지 만들기',
                      enabled: !_creating,
                      onTap: _onCreate),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepDots() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Container(
              width: i == step ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                  color: i <= step ? BC.oMain : BC.line,
                  borderRadius: BorderRadius.circular(4)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(String title, {String? sub, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(sub, style: const TextStyle(fontSize: 13, color: BC.ink2)),
            ],
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _chipRow(List<String> items, int sel, ValueChanged<int> onTap) {
    return Row(children: [
      for (int i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 7),
        Expanded(
            child: SelectChip(label: items[i], selected: sel == i, onTap: () => onTap(i))),
      ]
    ]);
  }

  // ───────────── step 0: 기본 정보 ─────────────
  Widget _basic() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
      children: [
        _card('1. 챌린지 제목',
            child: TextField(
              controller: _titleCtrl,
              maxLength: 200,
              decoration: _deco('예) 매일 아침 러닝'),
            )),
        _card('2. 카테고리',
            child: _chipRow(
                _categories, _categoryIndex, (i) => setState(() => _categoryIndex = i))),
        _card('3. 소개글',
            sub: '어떤 챌린지인지 짧게 소개해 주세요.',
            child: TextField(
              controller: _descCtrl,
              maxLines: 3,
              maxLength: 200,
              decoration: _deco('예) 매일 30분 러닝 인증하는 챌린지예요!'),
            )),
        _card('4. 기간',
            sub: '며칠 동안 진행할까요?',
            child: _chipRow([for (final d in _durations) '$d일'], _durationIndex,
                (i) => setState(() => _durationIndex = i))),
        _card('5. 정원',
            sub: '인원이 모이면 서버가 팀을 나눠 대결을 붙여요.',
            child: _chipRow([for (final c in _capacities) '$c명'], _capacityIndex,
                (i) => setState(() => _capacityIndex = i))),
        _card('6. 인증 방법',
            sub: 'GPS 위치 인증만 지원해요. 인증 위치는 참가할 때 각자 등록해요.',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                  color: BC.oSoft, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: const [
                  Icon(Icons.location_on_rounded, color: BC.oMain, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('GPS 위치 인증',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  Icon(Icons.check_circle_rounded, color: BC.oMain, size: 20),
                ],
              ),
            )),
        _card('7. 예치코인',
            sub: '참가할 때 각자 차감되는 코인이에요. 이긴 팀이 정산에서 나눠 가져요.',
            child: TextField(
              controller: _depositCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _deco('코인 수를 입력하세요').copyWith(
                suffixText: '코인',
                suffixStyle: const TextStyle(
                    color: BC.oMain, fontWeight: FontWeight.w700, fontSize: 14),
              ),
            )),
      ],
    );
  }

  // ───────────── step 1: 공개 설정 ─────────────
  Widget _visibility() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
      children: [
        _visCard(true, '공개', Icons.public_rounded, '탐색 목록에 노출돼요. 누구나 찾아서 참여할 수 있어요.'),
        const SizedBox(height: 12),
        _visCard(false, '비공개', Icons.lock_rounded, '탐색에 노출되지 않아요. 초대 코드를 아는 사람만 참여할 수 있어요.'),
        const SizedBox(height: 22),
        const Text('참가 승인 방식',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        _approvalCard(false, '자동 승인', Icons.bolt_rounded, '신청하면 바로 참가가 확정돼요.'),
        const SizedBox(height: 12),
        _approvalCard(true, '방장 승인', Icons.how_to_reg_rounded, '내가 승인해야 참가가 확정돼요.'),
        const SizedBox(height: 18),
        NoteBox(
          icon: Icons.verified_user_rounded,
          child: Text(
              isPublic
                  ? '정원이 차면 서버가 팀을 나눠 대결이 시작돼요.'
                  : '비공개 챌린지를 만들면 초대 코드가 발급돼요. 친구에게 코드를 공유해 모아보세요.',
              style: const TextStyle(fontSize: 13, color: BC.ink2, height: 1.5)),
        ),
      ],
    );
  }

  Widget _visCard(bool value, String title, IconData icon, String desc) =>
      _choiceCard(isPublic == value, title, icon, desc,
          () => setState(() => isPublic = value));

  Widget _approvalCard(bool value, String title, IconData icon, String desc) =>
      _choiceCard(_leaderApproval == value, title, icon, desc,
          () => setState(() => _leaderApproval = value));

  Widget _choiceCard(
      bool on, String title, IconData icon, String desc, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: on ? BC.oSoft : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? BC.oMain : BC.line, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: on ? BC.oMain : BC.bg, borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: on ? Colors.white : BC.ink3, size: 23),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: on ? BC.oMain : BC.ink)),
                  const SizedBox(height: 4),
                  Text(desc,
                      style: const TextStyle(fontSize: 12.5, color: BC.ink2, height: 1.4)),
                ],
              ),
            ),
            Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: on ? BC.oMain : BC.ink3),
          ],
        ),
      ),
    );
  }

  Future<void> _onCreate() async {
    final deposit = int.tryParse(_depositCtrl.text.trim());
    if (deposit == null || deposit < 0) {
      showBoosterToast(context, '예치코인을 입력해주세요');
      return;
    }
    setState(() => _creating = true);
    try {
      final description = _descCtrl.text.trim();
      final challenge = await ChallengeService.create(CreateChallengeRequest(
        category: _categories[_categoryIndex],
        title: _titleCtrl.text.trim(),
        description: description.isEmpty ? null : description,
        durationDays: _durations[_durationIndex],
        depositCoins: deposit,
        visibility: isPublic ? 'PUBLIC' : 'PRIVATE',
        approvalType: _leaderApproval ? 'LEADER' : 'AUTO',
        maxParticipants: _capacities[_capacityIndex],
      ));
      if (!mounted) return;
      Session.currentChallengeId = challenge.id;

      // 비공개 챌린지는 서버가 발급한 초대 코드를 바로 보여준다.
      final inviteCode = challenge.inviteCode;
      if (!isPublic && inviteCode != null && inviteCode.isNotEmpty) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => OwnerCodeScreen(code: inviteCode, challenge: challenge)));
      } else {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => TeamWaitingScreen(challenge: challenge)));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: BC.ink3),
        counterText: '',
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: BC.line, width: 1.5)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: BC.oMain, width: 1.5)),
      );
}

/// 비공개 챌린지 생성 직후 — 초대 코드 공유 + 모집 현황.
///
/// 코드는 서버가 발급한 `Challenge.inviteCode`다. 상대는
/// `GET /api/challenges/invite/{code}`로 이 챌린지를 찾아 참가한다.
class OwnerCodeScreen extends StatefulWidget {
  final String code;
  final Challenge challenge;
  const OwnerCodeScreen({super.key, required this.code, required this.challenge});

  @override
  State<OwnerCodeScreen> createState() => _OwnerCodeScreenState();
}

class _OwnerCodeScreenState extends State<OwnerCodeScreen> {
  late Challenge _challenge = widget.challenge;
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final latest = await ChallengeService.fetchDetail(_challenge.id);
      if (!mounted) return;
      setState(() => _challenge = latest);
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.code;
    final cur = _challenge.confirmedCount ?? 0;
    final cap = _challenge.maxParticipants;
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        child: Column(
          children: [
            const BackAppBar(title: '방장 화면'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: BC.oMain,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration:
                            const BoxDecoration(color: BC.oSoft, shape: BoxShape.circle),
                        child: const Icon(Icons.lock_rounded, color: BC.oMain, size: 30),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('비공개 챌린지가 만들어졌어요',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text('아래 초대 코드를 친구에게 공유해 팀원을 모아보세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13.5, color: BC.ink2)),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
                      decoration: BoxDecoration(
                        gradient: BC.grad,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: BC.ctaShadow,
                      ),
                      child: Column(
                        children: [
                          const Text('초대 코드',
                              style: TextStyle(color: Colors.white70, fontSize: 13)),
                          const SizedBox(height: 6),
                          FittedBox(
                            child: Text(code,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 40,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 6)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _ghostBtn(Icons.copy_rounded, '코드 복사', () {
                      Clipboard.setData(ClipboardData(text: code));
                      showBoosterToast(context, '초대 코드를 복사했어요.');
                    }),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Text('모집 현황',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const Spacer(),
                        if (_refreshing)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: BC.oMain, strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF8F7F5),
                          borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: [
                          Row(children: [
                            Text('$cur / $cap명',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            const Spacer(),
                            const Text('방장(나) 포함',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: BC.ink2,
                                    fontWeight: FontWeight.w600)),
                          ]),
                          const SizedBox(height: 12),
                          Wrap(spacing: 7, runSpacing: 7, children: [
                            for (int i = 0; i < cur; i++)
                              Container(
                                width: 34,
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                    color: i == 0 ? BC.oMain : const Color(0xFFF0997B),
                                    shape: BoxShape.circle),
                                child: i == 0
                                    ? const Text('나',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700))
                                    : const Icon(Icons.person_rounded,
                                        size: 16, color: Colors.white),
                              ),
                            for (int i = 0; i < (cap - cur); i++)
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: const Color(0xFFD6D4CF), width: 1.5)),
                                child: const Icon(Icons.add_rounded,
                                    size: 15, color: Color(0xFFC2C0BB)),
                              ),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    // 챌린지 시작은 서버가 정원 충족 시 처리한다(앱에 시작 API가 없다).
                    NoteBox(
                      icon: Icons.info_outline_rounded,
                      child: const Text('정원이 차면 서버가 팀을 편성하고 챌린지를 시작해요.',
                          style: TextStyle(fontSize: 13, color: BC.ink2, height: 1.5)),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: PrimaryButton(
                label: '챌린지 현황 보기',
                onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                    builder: (_) => TeamWaitingScreen(challenge: _challenge))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ghostBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BC.line, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: BC.oMain),
            const SizedBox(width: 7),
            Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: BC.ink)),
          ],
        ),
      ),
    );
  }
}
