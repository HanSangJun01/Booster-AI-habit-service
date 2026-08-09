import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../models/challenge.dart';
import '../../models/settlement.dart';
import '../../models/team.dart';
import '../../services/challenge_service.dart';
import '../../services/settlement_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../main_scaffold.dart';

/// 팀 배틀 화면 — `GET /api/challenges/{challengeId}/team-detail`.
///
/// 서버가 내 팀과 상대 팀을 한 응답으로 준다(`TeamDetailResponse`): 팀명,
/// 참여율, 오늘 인증한 인원, 전체 인원, 팀원별 인증 여부, 진행 일차까지.
/// 예전처럼 리더보드에서 우리 팀을 추측해 찾을 필요가 없다.
///
/// 챌린지가 끝나 정산이 완료되면 `GET /api/challenges/{id}/result`로 승패와
/// 상금을 받아 함께 보여준다.
class TeamBattleScreen extends StatefulWidget {
  final Challenge challenge;
  const TeamBattleScreen({super.key, required this.challenge});

  @override
  State<TeamBattleScreen> createState() => _TeamBattleScreenState();
}

class _TeamBattleScreenState extends State<TeamBattleScreen> {
  bool _loading = true;
  TeamDetail? _detail;
  SettlementResult? _settlement;
  String? _error;

  Challenge get _challenge => widget.challenge;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final detail = await ChallengeService.fetchTeamDetail(_challenge.id);
      // 정산은 챌린지가 끝나야 생긴다 — 없으면 null이 온다.
      final settlement = await SettlementService.fetchResult(_challenge.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _settlement = settlement;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
      });
    } finally {
      // 어떤 예외로 빠져나가든 스피너는 반드시 걷는다.
      if (mounted) setState(() => _loading = false);
    }
  }

  TeamSide? get _myTeam => _detail?.myTeam;
  TeamSide? get _opponent => _detail?.opponentTeam;

  /// 두 팀 참여율을 100% 기준으로 나눈 값. 둘 다 0이면 반반으로 둔다.
  int get _myShare {
    final mine = _myTeam?.participationRate ?? 0;
    final theirs = _opponent?.participationRate ?? 0;
    final total = mine + theirs;
    if (total <= 0) return 50;
    return ((mine / total) * 100).round();
  }

  int get _opponentShare => 100 - _myShare;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const BackAppBar(title: '팀 배틀'),
            Expanded(child: _body()),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: BC.oMain));
    }
    if (_detail == null || _myTeam == null) return _emptyState();

    final hasOpponent = _opponent != null;
    return RefreshIndicator(
      onRefresh: _load,
      color: BC.oMain,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
        children: [
          if (_settlement != null) ...[
            _settlementCard(_settlement!),
            const SizedBox(height: 14),
          ],
          _vsHero(hasOpponent),
          const SizedBox(height: 14),
          _leadCard(hasOpponent),
          const SizedBox(height: 12),
          _participation(hasOpponent),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _tpCard(Icons.hourglass_bottom_rounded, '진행', _progressText(),
                    const Color(0xFFF6F5F3), BC.ink2)),
            const SizedBox(width: 12),
            Expanded(
                child: _tpCard(Icons.monetization_on_rounded, '우승 상금', _prizeText(),
                    const Color(0xFFFFF6E0), const Color(0xFFF0A500))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _statCard(_myTeam!, ours: true)),
            const SizedBox(width: 12),
            Expanded(
                child: hasOpponent
                    ? _statCard(_opponent!, ours: false)
                    : _noOpponentCard()),
          ]),
          const SizedBox(height: 12),
          _todayMembers(),
          const SizedBox(height: 12),
          _rules(),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.emoji_events_outlined, size: 56, color: BC.ink3),
            const SizedBox(height: 16),
            Text(_error ?? '${_challenge.title}의\n팀 대결 정보가 아직 없어요',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: BC.ink2)),
            const SizedBox(height: 8),
            const Text('정원이 차서 팀이 편성되면 여기에서 상대 팀과의\n참여율 대결을 확인할 수 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: BC.ink3, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: BC.line)),
      ),
      child: PrimaryButton(
        label: '인증하러 가기',
        leadingIcon: Icons.location_on_rounded,
        onTap: () {
          MainNavScope.of(context).select(2);
          Navigator.of(context).popUntil((r) => r.isFirst);
        },
      ),
    );
  }

  String _progressText() {
    final detail = _detail;
    if (detail == null) return '-';
    final day = detail.challengeDay;
    if (day == null) return '시작 전';
    return '$day일차 / ${detail.totalDays}일';
  }

  /// 우승 상금. 정산 전에는 전체 예치금 규모(예치금 × 정원)를 예상치로 보여준다.
  String _prizeText() {
    final settlement = _settlement;
    if (settlement != null) {
      return '${CoinPill.format(settlement.perWinnerPayout)} 코인';
    }
    if (_challenge.depositCoins <= 0) return '없음';
    final pot = _challenge.depositCoins * _challenge.maxParticipants;
    return '${CoinPill.format(pot)} 코인';
  }

  /// 정산 결과 배너. 승패는 내 팀 id와 winnerTeamId를 비교해 판정한다.
  Widget _settlementCard(SettlementResult settlement) {
    final myTeamId = _myTeam?.teamId;
    final won = !settlement.draw &&
        myTeamId != null &&
        settlement.winnerTeamId == myTeamId;
    final color = settlement.draw ? BC.blue : (won ? BC.green : const Color(0xFFE5484D));
    final label = settlement.draw ? '무승부' : (won ? '승리!' : '패배');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .35), width: 1.4)),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(
                settlement.draw
                    ? Icons.handshake_rounded
                    : (won ? Icons.emoji_events_rounded : Icons.sentiment_dissatisfied_rounded),
                color: Colors.white,
                size: 25),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: color)),
                const SizedBox(height: 3),
                Text(
                  settlement.draw
                      ? '예치 코인이 전원에게 환불됐어요.'
                      : (won
                          ? '1인당 ${CoinPill.format(settlement.perWinnerPayout)}코인을 받았어요.'
                          : '이번엔 아쉬웠어요. 다음 챌린지에서 만회해봐요.'),
                  style: const TextStyle(fontSize: 13, color: BC.ink2, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vsHero(bool hasOpponent) {
    final myName = _myTeam?.teamName ?? '우리 팀';
    final opponentName = _opponent?.teamName ?? '상대 팀';
    return SizedBox(
      height: 172,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Color(0xFFFF7A3D), Color(0xFFF0440A)])),
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Color(0xFF3D7BFB), Color(0xFF1A52D8)])),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                  child: _vsCol(Icons.local_fire_department_rounded, myName,
                      hasOpponent ? '$_myShare' : null, BC.oMain)),
              Expanded(
                  child: _vsCol(Icons.water_drop_rounded, opponentName,
                      hasOpponent ? '$_opponentShare' : null, BC.blue)),
            ],
          ),
          const Center(
            child: Text('VS',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic)),
          ),
        ],
      ),
    );
  }

  Widget _vsCol(IconData icon, String name, String? pct, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 27),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
        ),
        Text(pct != null ? '$pct%' : '집계 전',
            style: TextStyle(
                color: Colors.white,
                fontSize: pct != null ? 30 : 18,
                fontWeight: FontWeight.w800)),
        const Text('점유율',
            style: TextStyle(
                color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _leadCard(bool hasOpponent) {
    Widget content;
    if (!hasOpponent) {
      content = const Text('아직 상대 팀이 정해지지 않았어요',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800));
    } else {
      final mine = _myTeam!.participationPercent;
      final theirs = _opponent!.participationPercent;
      final diff = (mine - theirs).abs();
      final weAhead = mine >= theirs;
      final leaderName = weAhead ? _myTeam!.teamName : _opponent!.teamName;
      final leaderColor = weAhead ? BC.oMain : BC.blue;
      content = Column(
        children: [
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: '🔥 '),
              TextSpan(
                  text: leaderName,
                  style: TextStyle(color: leaderColor, fontWeight: FontWeight.w800)),
              TextSpan(
                  text: diff == 0 ? '와 접전 중!' : '가 $diff%p 앞서는 중!',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            style: const TextStyle(fontSize: 17),
          ),
          const SizedBox(height: 5),
          const Text('누적 인증 참여율 기준',
              style:
                  TextStyle(fontSize: 12.5, color: BC.ink3, fontWeight: FontWeight.w600)),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      width: double.infinity,
      decoration: BoxDecoration(
          border: Border.all(color: BC.line), borderRadius: BorderRadius.circular(16)),
      child: content,
    );
  }

  Widget _participation(bool hasOpponent) {
    final mine = _myTeam?.participationPercent ?? 0;
    final theirs = _opponent?.participationPercent ?? 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          border: Border.all(color: BC.line), borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((_myTeam?.teamName ?? '우리 팀').toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: BC.oMain)),
                    Text('$mine%',
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800, color: BC.oMain)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text((_opponent?.teamName ?? '상대 팀').toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: BC.blue)),
                    Text(hasOpponent ? '$theirs%' : '집계 전',
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800, color: BC.blue)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Expanded(
                    flex: _myShare == 0 ? 1 : _myShare,
                    child: Container(height: 12, color: BC.oMain)),
                Expanded(
                    flex: _opponentShare == 0 ? 1 : _opponentShare,
                    child: Container(height: 12, color: BC.blue)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tpCard(
      IconData icon, String label, String value, Color iconBg, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          border: Border.all(color: BC.line), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 21, color: iconColor),
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

  Widget _statCard(TeamSide side, {required bool ours}) {
    final color = ours ? BC.oMain : BC.blue;
    final bg = ours ? BC.oSoft : BC.blueSoft;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${ours ? '우리 팀' : '상대 팀'} (${side.teamName})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 12),
          _statRow(Icons.people_alt_rounded, '참여 인원', '${side.totalMemberCount}명', color),
          const SizedBox(height: 11),
          _statRow(Icons.check_circle_rounded, '오늘 인증',
              '${side.todayCheckedInCount}/${side.totalMemberCount}', color),
        ],
      ),
    );
  }

  Widget _statRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11.5, color: BC.ink2, fontWeight: FontWeight.w600)),
            Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
      ],
    );
  }

  Widget _noOpponentCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: BC.bg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('상대 팀',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: BC.ink3)),
          SizedBox(height: 12),
          Text('아직 편성되지 않았어요',
              style: TextStyle(fontSize: 13, color: BC.ink3, height: 1.5)),
        ],
      ),
    );
  }

  /// 오늘 우리 팀원들의 인증 현황. 서버가 팀원별 상태를 함께 준다.
  Widget _todayMembers() {
    final members = _myTeam?.members ?? const [];
    if (members.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          border: Border.all(color: BC.line), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.today_rounded, size: 19, color: BC.oMain),
            SizedBox(width: 8),
            Text('우리 팀 오늘 인증',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final member in members)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: member.checkedIn ? BC.greenSoft : const Color(0xFFF1F2F5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                          member.checkedIn
                              ? Icons.check_rounded
                              : Icons.schedule_rounded,
                          size: 20,
                          color: member.checkedIn ? BC.green : BC.ink3),
                    ),
                    const SizedBox(height: 4),
                    Text(member.checkedIn ? '완료' : '대기',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: member.checkedIn ? BC.green : BC.ink3)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rules() {
    Widget li(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 7, right: 8),
                width: 4,
                height: 4,
                decoration: const BoxDecoration(color: BC.oMain, shape: BoxShape.circle),
              ),
              Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 13.5, color: BC.ink2, height: 1.55)),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: const Color(0xFFF8F7F5), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.fact_check_rounded, size: 19, color: BC.oMain),
            SizedBox(width: 8),
            Text('배틀 규칙', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 11),
          li('참여율 = 팀 누적 인증 ÷ (챌린지 기간 × 팀 인원)'),
          li('종료 시 참여율이 더 높은 팀이 승리해요'),
          li('승리 팀이 전체 예치 코인을 인원수로 나눠 가져요 (동률 시 전원 환불)'),
        ],
      ),
    );
  }
}
