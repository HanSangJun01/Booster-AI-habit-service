import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../models/challenge.dart';
import '../../models/challenge_category.dart';
import '../../models/personal_location.dart';
import '../../services/challenge_service.dart';
import '../../services/personal_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../home/personal_create_screen.dart';
import 'team_waiting_screen.dart';

/// 챌린지 생성 — `POST /api/challenges` (`CreateChallengeRequest`).
///
/// 예전의 "팀 만들기"가 이것이다. 백엔드에는 팀 생성 API가 없고, 팀은 챌린지에
/// 사람이 모이면 서버가 편성한다.
///
/// 서버가 검증하는 값: durationDays >= 1, **depositCoins >= 100**,
/// **maxParticipants = 10 고정**, category 는 `EXERCISE`/`STUDY`,
/// verificationType 은 `GPS_PHOTO_AI` 하나.
///
/// 이름은 받지 않는다 — 비워 보내면 서버가 "운동 · 방장닉네임"으로 만든다.
///
/// 화면에 보이는 카테고리 이름과 서버로 보내는 값은 다르다
/// ([ChallengeCategory]) — 한글을 그대로 보내면 AI 인증이 전부 실패한다.
///
/// 방장은 생성과 동시에 CONFIRMED 참가자가 되고 예치금도 같이 차감된다. 그래서
/// 인증 위치가 필요하고, 없으면 생성 자체가 400으로 막힌다 — [_onCreate]가
/// 먼저 확인한다.
class TeamCreateScreen extends StatefulWidget {
  const TeamCreateScreen({super.key});
  @override
  State<TeamCreateScreen> createState() => _TeamCreateScreenState();
}

class _TeamCreateScreenState extends State<TeamCreateScreen> {
  int step = 0; // 0 기본, 1 공개설정

  /// 화면에 보이는 이름과 서버로 보내는 값이 다르다([ChallengeCategory]).
  static const _categories = ChallengeCategory.choices;
  int _categoryIndex = 0;

  ChallengeCategory get _category => _categories[_categoryIndex];

  // 인증 방식은 고를 수 없다. 위치만·사진만은 각각 우회가 쉬워
  // CreateChallengeRequest.fixedVerificationType 하나로 정해졌고, 서버도 그 값만 받는다.

  static const _durations = [7, 14, 21, 30];
  int _durationIndex = 1;

  /// 정원은 고를 수 없다 — 서버가 10명으로 못 박았다(`@Min(10) @Max(10)`).
  ///
  /// 팀 편성이 "10명이 차면 5:5"라서, 4·6·8명으로 만들면 정원을 채워도 팀이
  /// 안 짜이고 아무도 인증할 수 없는 챌린지가 된다. 예전엔 그런 값을 고를 수
  /// 있었고, 지금 그대로 보내면 400으로 거절당한다.
  static const _capacity = 10;

  bool isPublic = true;

  /// 방장의 인증 기준 위치. 없으면 챌린지를 만들 수 없다.
  PersonalLocation? _location;
  bool _locationChecked = false;

  /// 참가 승인 방식. AUTO면 신청 즉시 확정, LEADER면 방장이 승인해야 한다.
  bool _leaderApproval = false;

  bool _creating = false;

  final _descCtrl = TextEditingController();
  final _depositCtrl = TextEditingController(text: '300');

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  /// 방장의 개인 인증 위치를 미리 확인한다. 조회에 실패하면 없는 것으로 두지
  /// 않고(=경고를 띄우지 않고) 넘어간다 — 실제 판정은 서버가 한다.
  Future<void> _loadLocation() async {
    try {
      final location = await PersonalService.fetchLocation();
      if (!mounted) return;
      setState(() {
        _location = location;
        _locationChecked = true;
      });
    } on ApiException {
      // 조회 실패는 "위치 없음"과 다르다. 경고를 띄우지 않고 생성 시점에 맡긴다.
    }
  }

  @override
  void dispose() {
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
                      onTap: () => setState(() => step = 1))
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
        // 이름은 더 이상 받지 않는다. 카테고리만 고르면 서버가
        // "운동 · 방장닉네임"으로 만들어 목록에서 구분되게 한다.
        _card('1. 카테고리',
            sub: '무슨 습관을 함께 만들까요?',
            child: _chipRow([for (final c in _categories) c.label], _categoryIndex,
                (i) => setState(() => _categoryIndex = i))),
        _card('2. 소개글',
            sub: '어떤 챌린지인지 짧게 소개해 주세요.',
            child: TextField(
              controller: _descCtrl,
              maxLines: 3,
              maxLength: 200,
              decoration: _deco('예) 매일 30분 러닝 인증하는 챌린지예요!'),
            )),
        _card('3. 기간',
            sub: '며칠 동안 진행할까요?',
            child: _chipRow([for (final d in _durations) '$d일'], _durationIndex,
                (i) => setState(() => _durationIndex = i))),
        _card('4. 정원',
            sub: '$_capacity명이 모이면 서버가 5:5로 팀을 나눠 대결을 붙여요.',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration:
                  BoxDecoration(color: BC.oSoft, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: const [
                  Icon(Icons.groups_rounded, color: BC.oMain, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('$_capacity명 고정',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  Icon(Icons.check_circle_rounded, color: BC.oMain, size: 20),
                ],
              ),
            )),
        // 인증 방법은 고를 수 없다 — 위치만·사진만은 각각 우회가 쉬워
        // "위치 + 사진" 하나로 정해졌다(서버도 그 값만 받는다).
        _card('5. 인증 방법',
            sub: '등록한 장소에서 사진까지 올려야 인증돼요.',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration:
                  BoxDecoration(color: BC.oSoft, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: const [
                  Icon(Icons.add_location_alt_rounded, color: BC.oMain, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('위치 + 사진',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  Icon(Icons.check_circle_rounded, color: BC.oMain, size: 20),
                ],
              ),
            )),
        _card('6. 예치코인',
            sub: '참가할 때 각자 차감돼요. 이긴 팀이 정산에서 나눠 가져요. '
                '${CreateChallengeRequest.minDepositCoins}코인부터 걸 수 있어요.',
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
        const SizedBox(height: 12),
        // 방장도 참가자다 — 만드는 순간 인원 1명이 차고 예치금도 빠진다.
        // 모르고 만들면 코인이 왜 줄었는지 알 수 없어서 미리 알린다.
        NoteBox(
          icon: Icons.account_balance_wallet_rounded,
          child: Text(
              '챌린지를 만들면 나도 바로 참가자가 돼요. 예치코인도 같이 차감돼요.',
              style: const TextStyle(fontSize: 13, color: BC.ink2, height: 1.5)),
        ),
        if (_locationChecked && _location == null) ...[
          const SizedBox(height: 12),
          const NoteBox(
            icon: Icons.location_off_rounded,
            bg: BC.blueSoft,
            iconColor: BC.blue,
            child: Text(
                '인증 장소가 아직 없어요. 만들기를 누르면 등록 화면으로 안내할게요.',
                style: TextStyle(fontSize: 13, color: BC.ink2, height: 1.5)),
          ),
        ],
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

  /// 인증 위치를 확보한다. 없으면 등록 화면으로 보내고, 등록하고 돌아오면
  /// 그대로 생성을 이어간다.
  ///
  /// 서버 에러를 그냥 띄우면("인증 위치가 필요합니다") 어디서 뭘 해야 하는지
  /// 알 수 없다 — 위치 등록은 팀 탭이 아니라 홈에 있다.
  Future<bool> _ensureLocation() async {
    if (_location != null) return true;

    showBoosterToast(context, '먼저 인증 장소를 등록해주세요');
    final registered = await Navigator.of(context).push<PersonalLocation>(
        MaterialPageRoute(builder: (_) => const PersonalCreateScreen()));
    if (!mounted) return false;
    if (registered == null) return false;

    setState(() {
      _location = registered;
      _locationChecked = true;
    });
    return true;
  }

  Future<void> _onCreate() async {
    final deposit = int.tryParse(_depositCtrl.text.trim());
    if (deposit == null) {
      showBoosterToast(context, '예치코인을 입력해주세요');
      return;
    }
    // 서버가 100코인 하한을 검증한다. 여기서 걸러야 400을 받고 나서야 알게 되는 걸 막는다.
    if (deposit < CreateChallengeRequest.minDepositCoins) {
      showBoosterToast(context,
          '예치코인은 ${CreateChallengeRequest.minDepositCoins}코인 이상이어야 해요');
      return;
    }
    if (!await _ensureLocation()) return;
    if (!mounted) return;
    setState(() => _creating = true);
    try {
      final description = _descCtrl.text.trim();
      // _ensureLocation을 통과했으니 위치가 있다. 서버의 암묵적 재사용에 기대지
      // 않고 앱이 아는 좌표를 그대로 실어 보낸다.
      final location = _location;
      final challenge = await ChallengeService.create(CreateChallengeRequest(
        // 화면에 보인 건 '운동'이지만 서버로는 EXERCISE가 나간다. 한글을 그대로
        // 보내면 AI 인증에서 사진 업로드가 500으로 터진다.
        category: _category.value,
        // 이름은 보내지 않는다 — 서버가 "운동 · 방장닉네임"으로 만들어 준다.
        description: description.isEmpty ? null : description,
        verificationType: CreateChallengeRequest.fixedVerificationType,
        durationDays: _durations[_durationIndex],
        depositCoins: deposit,
        visibility: isPublic ? 'PUBLIC' : 'PRIVATE',
        approvalType: _leaderApproval ? 'LEADER' : 'AUTO',
        maxParticipants: _capacity,
        gpsLat: location?.lat,
        gpsLng: location?.lng,
        gpsRadiusMeters: location?.radiusMeters,
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
