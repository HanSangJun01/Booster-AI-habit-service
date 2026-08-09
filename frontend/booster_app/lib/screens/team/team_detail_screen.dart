import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/location.dart';
import '../../core/session.dart';
import '../../models/challenge.dart';
import '../../models/participant.dart';
import '../../services/challenge_service.dart';
import '../../services/participant_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import 'team_waiting_screen.dart';

/// 챌린지 상세 + 참가 신청 — `POST /api/challenges/{challengeId}/participants`.
///
/// 참가할 때 **인증 기준 위치를 함께 등록**해야 한다(`ParticipationRequest`의
/// gpsLat/gpsLng/gpsRadiusMeters가 필수). 이후 이 좌표와 반경으로 팀 챌린지
/// 인증이 판정된다. 그래서 참여 버튼은 바로 신청하지 않고 위치 확인 시트를 먼저 연다.
class TeamDetailScreen extends StatefulWidget {
  final Challenge challenge;
  const TeamDetailScreen({super.key, required this.challenge});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  late Challenge _challenge = widget.challenge;
  bool _joining = false;
  bool _joined = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// 목록 응답에는 confirmedCount가 없어서(상세 전용 필드) 상세를 다시 부른다.
  Future<void> _refresh() async {
    try {
      final latest = await ChallengeService.fetchDetail(_challenge.id);
      if (!mounted) return;
      setState(() => _challenge = latest);
    } on ApiException catch (_) {
      // 상세 조회 실패는 화면을 막을 정도는 아니다 — 목록에서 받은 값으로 그린다.
    }
  }

  Future<void> _join() async {
    final setup = await showModalBottomSheet<_JoinSetup>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _JoinLocationSheet(),
    );
    if (setup == null || !mounted) return;

    setState(() => _joining = true);
    try {
      final participant = await ParticipantService.apply(
        _challenge.id,
        ParticipationRequest(
          personalStatement: setup.statement,
          gpsLat: setup.latitude,
          gpsLng: setup.longitude,
          gpsRadiusMeters: setup.radiusMeters,
          gpsPlaceName: setup.placeName,
        ),
      );
      if (!mounted) return;
      setState(() => _joined = true);
      Session.currentChallengeId = _challenge.id;

      showBoosterToast(
          context,
          participant.isConfirmed
              ? '참가가 확정됐어요!'
              : '참가 신청을 보냈어요. 방장 승인을 기다려주세요.');
      final latest = await ChallengeService.fetchDetail(_challenge.id);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => TeamWaitingScreen(challenge: latest)));
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
      setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = _challenge.confirmedCount ?? 0;
    final cap = _challenge.maxParticipants;
    final remaining = (cap - cur).clamp(0, cap);

    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        child: Column(
          children: [
            BackAppBar(title: '챌린지 상세', trailing: const CoinPill()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
                children: [
                  Container(
                    height: 170,
                    decoration: BoxDecoration(
                        gradient: BC.grad, borderRadius: BorderRadius.circular(18)),
                    child: const Icon(Icons.flag_rounded, color: Colors.white70, size: 44),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Flexible(
                      child: Text(_challenge.title,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4)),
                    ),
                    const SizedBox(width: 9),
                    MiniTag(_challenge.isPrivate ? '비공개' : '공개',
                        bg: BC.oSoft, fg: BC.oMain),
                  ]),
                  const SizedBox(height: 8),
                  Text(_challenge.description ?? '소개글이 없어요.',
                      style: const TextStyle(
                          fontSize: 15, color: BC.ink2, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    MiniTag(_challenge.category),
                    MiniTag('${_challenge.durationDays}일'),
                    MiniTag(_challenge.needsLeaderApproval ? '방장 승인' : '자동 승인'),
                  ]),

                  // 모집 현황
                  _secTitle('모집 현황'),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF8F7F5),
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text.rich(TextSpan(children: [
                              TextSpan(
                                  text: '$cur',
                                  style: const TextStyle(
                                      color: BC.oMain,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800)),
                              TextSpan(
                                  text: ' / $cap명',
                                  style: const TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w700)),
                            ])),
                            const Spacer(),
                            Text(
                                remaining == 0
                                    ? '정원이 찼어요'
                                    : '$remaining명 모이면 배틀 시작',
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: BC.ink2,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: cap == 0 ? 0 : (cur / cap).clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: const Color(0xFFE8E6E2),
                            valueColor: const AlwaysStoppedAnimation(BC.oMain),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            for (int i = 0; i < cap; i++)
                              i < cur
                                  ? Container(
                                      width: 34,
                                      height: 34,
                                      alignment: Alignment.center,
                                      decoration: const BoxDecoration(
                                          color: BC.oMain, shape: BoxShape.circle),
                                      child: const Icon(Icons.person_rounded,
                                          size: 17, color: Colors.white),
                                    )
                                  : Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: const Color(0xFFD6D4CF),
                                              width: 1.5)),
                                      child: const Icon(Icons.add_rounded,
                                          size: 15, color: Color(0xFFC2C0BB)),
                                    ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 챌린지 정보
                  _secTitle('챌린지 정보'),
                  Row(children: [
                    Expanded(
                        child: _infoCard(Icons.calendar_today_rounded, '기간',
                            '${_challenge.durationDays}일')),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _infoCard(Icons.location_on_rounded, '인증 방법',
                            _challenge.verificationType)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: _infoCard(
                            Icons.category_rounded, '카테고리', _challenge.category)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _infoCard(Icons.how_to_reg_rounded, '승인',
                            _challenge.needsLeaderApproval ? '방장 승인' : '자동')),
                  ]),

                  // 대결 방식
                  _secTitle('팀 대결 방식'),
                  Container(
                    decoration: BoxDecoration(
                        border: Border.all(color: BC.line),
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        _ruleRow(Icons.groups_rounded, '팀 배틀',
                            '정원이 차면 서버가 두 팀으로 나눠 챌린지를 시작해요.'),
                        const Divider(height: 1, color: BC.line),
                        _ruleRow(Icons.bar_chart_rounded, '참여율로 승부',
                            '기간 동안 팀 누적 인증 참여율이 더 높은 팀이 이겨요.'),
                        const Divider(height: 1, color: BC.line),
                        _ruleRow(Icons.emoji_events_rounded, '승리 보상',
                            '이긴 팀이 예치 코인을 나눠 갖고, 비기면 전원 환불돼요.'),
                      ],
                    ),
                  ),

                  // 예치코인
                  _secTitle('예치코인'),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: BC.oSoft,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFBD9C7)),
                    ),
                    child: Column(
                      children: [
                        Row(children: [
                          const CoinDot(size: 28, symbol: '\$'),
                          const SizedBox(width: 9),
                          const Text('참여 시 차감돼요',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: BC.o2)),
                          const Spacer(),
                          Text.rich(TextSpan(children: [
                            TextSpan(
                                text: CoinPill.format(_challenge.depositCoins),
                                style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: BC.oMain)),
                            const TextSpan(
                                text: '코인',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: BC.oMain)),
                          ])),
                        ]),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Divider(height: 1, color: Color(0xFFFBDDCD)),
                        ),
                        Row(children: const [
                          Icon(Icons.verified_user_rounded, size: 18, color: BC.oMain),
                          SizedBox(width: 7),
                          Expanded(
                            child: Text('잔액이 모자라면 참가할 수 없어요. 참가를 취소하면 환불돼요.',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: BC.ink2,
                                    fontWeight: FontWeight.w600,
                                    height: 1.45)),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 참여 CTA
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: BC.line)),
              ),
              child: _joined || !_challenge.isReady
                  ? Container(
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: const Color(0xFFD4D2CD),
                          borderRadius: BorderRadius.circular(16)),
                      child: Text(_joined ? '참여 완료' : '모집이 끝난 챌린지예요',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                    )
                  : PrimaryButton(
                      label: _joining
                          ? '참여하는 중...'
                          : '${CoinPill.format(_challenge.depositCoins)}코인 걸고 참여하기',
                      leadingIcon: Icons.monetization_on_rounded,
                      enabled: !_joining,
                      onTap: _join,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 22, 0, 12),
        child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _infoCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          color: const Color(0xFFF8F7F5), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration:
                BoxDecoration(color: BC.oSoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: BC.oMain),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: BC.ink2, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleRow(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration:
                const BoxDecoration(color: Color(0xFFFFEDE4), shape: BoxShape.circle),
            child: Icon(icon, size: 21, color: BC.oMain),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(desc,
                    style: const TextStyle(fontSize: 12.5, color: BC.ink2, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 참가 신청에 필요한 값 묶음.
class _JoinSetup {
  final double latitude;
  final double longitude;
  final int radiusMeters;
  final String? placeName;
  final String? statement;

  _JoinSetup({
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.placeName,
    this.statement,
  });
}

/// 참가 전 인증 위치를 잡는 시트.
///
/// 서버가 gpsLat/gpsLng/gpsRadiusMeters를 필수로 받기 때문에, 위치를 못 받으면
/// 참가 자체를 진행할 수 없다.
class _JoinLocationSheet extends StatefulWidget {
  const _JoinLocationSheet();
  @override
  State<_JoinLocationSheet> createState() => _JoinLocationSheetState();
}

class _JoinLocationSheetState extends State<_JoinLocationSheet> {
  static const _radiusOptions = [50, 100, 200, 500];
  int _radiusIndex = 1;

  final _statementCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();

  double? _latitude;
  double? _longitude;
  bool _locating = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  @override
  void dispose() {
    _statementCtrl.dispose();
    _placeCtrl.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final position = await LocationService.current();
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
    } on LocationException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      // 권한 확인·요청 단계에서 geolocator가 던지는 PlatformException 등.
      // 안 받으면 _locating이 true로 남아 "이 위치로 참가하기"가 영영
      // 비활성이 되고, 시트를 닫는 것 말고는 챌린지에 참가할 길이 없어진다.
      if (!mounted) return;
      setState(() => _error = '위치를 확인하지 못했어요. 잠시 후 다시 시도해주세요');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lat = _latitude;
    final lng = _longitude;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
            22, 14, 22, 20 + MediaQuery.of(context).padding.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration:
                      BoxDecoration(color: BC.line, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 20),
              const Text('인증 위치 등록',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('이 챌린지에서 인증할 기준 위치예요. 참가 후에는 이 반경 안에서만 인증할 수 있어요.',
                  style: TextStyle(fontSize: 13, color: BC.ink2, height: 1.45)),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                decoration: BoxDecoration(
                    color: BC.bg, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    if (_locating)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child:
                            CircularProgressIndicator(color: BC.oMain, strokeWidth: 2.4),
                      )
                    else
                      Icon(
                        lat == null
                            ? Icons.location_disabled_rounded
                            : Icons.location_on_rounded,
                        color: lat == null ? BC.ink3 : BC.oMain,
                        size: 26,
                      ),
                    const SizedBox(height: 8),
                    Text(
                      _locating
                          ? '현재 위치를 확인하는 중…'
                          : (lat == null || lng == null
                              ? (_error ?? '위치를 확인하지 못했어요')
                              : '위도 ${lat.toStringAsFixed(5)}, 경도 ${lng.toStringAsFixed(5)}'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13, color: BC.ink2, fontWeight: FontWeight.w600),
                    ),
                    if (!_locating) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _detect,
                        child: const Text('다시 확인',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: BC.oMain)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text('인증 반경',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Row(children: [
                for (int i = 0; i < _radiusOptions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 7),
                  Expanded(
                    child: SelectChip(
                      label: '${_radiusOptions[i]}m',
                      selected: _radiusIndex == i,
                      onTap: () => setState(() => _radiusIndex = i),
                    ),
                  ),
                ]
              ]),
              const SizedBox(height: 18),
              const Text('장소 이름 (선택)',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                controller: _placeCtrl,
                maxLength: 200,
                decoration: _deco('예: 집 앞 헬스장'),
              ),
              const SizedBox(height: 6),
              const Text('참여 각오 (선택)',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                controller: _statementCtrl,
                maxLines: 2,
                decoration: _deco('방장에게 보여줄 한마디를 남겨보세요'),
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                label: '이 위치로 참가하기',
                enabled: lat != null && lng != null,
                onTap: () {
                  if (lat == null || lng == null) return;
                  Navigator.of(context).pop(_JoinSetup(
                    latitude: lat,
                    longitude: lng,
                    radiusMeters: _radiusOptions[_radiusIndex],
                    placeName: _placeCtrl.text.trim(),
                    statement: _statementCtrl.text.trim(),
                  ));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: BC.ink3),
        counterText: '',
        filled: true,
        fillColor: BC.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: BC.line, width: 1.5)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: BC.oMain, width: 1.5)),
      );
}
