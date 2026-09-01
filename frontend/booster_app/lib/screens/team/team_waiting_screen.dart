import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../models/challenge.dart';
import '../../models/challenge_category.dart';
import '../../services/challenge_service.dart';
import '../../services/participant_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import 'team_approval_screen.dart';
import 'team_battle_screen.dart';

/// 챌린지 모집 현황 — 아직 시작되지 않은(READY) 챌린지.
///
/// 다루는 값은 확정 인원(`confirmedCount`), 정원, 초대 코드, 참가 취소다.
///
/// `approvalType`이 `LEADER`인 챌린지에서는 **방장에게만** 승인 화면 진입점을
/// 띄운다([TeamApprovalScreen]). 대기자 목록은
/// `GET /api/challenges/{id}/participants?status=PENDING`으로 받는다 — 예전에는
/// 이 경로를 안 써서 승인에 필요한 participantId를 얻을 방법이 없었고, 그래서
/// LEADER 챌린지는 정원이 영영 안 차 시작조차 못 했다.
class TeamWaitingScreen extends StatefulWidget {
  final Challenge challenge;
  const TeamWaitingScreen({super.key, required this.challenge});
  @override
  State<TeamWaitingScreen> createState() => _TeamWaitingScreenState();
}

class _TeamWaitingScreenState extends State<TeamWaitingScreen> {
  late Challenge _challenge = widget.challenge;
  bool _refreshing = false;
  bool _leaving = false;

  bool get _isOwner =>
      Session.userId != null && Session.userId == _challenge.createdBy;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final latest = await ChallengeService.fetchDetail(_challenge.id);
      if (!mounted) return;
      setState(() => _challenge = latest);
      // 모집이 끝나 시작된 상태면 바로 배틀 화면으로 넘긴다.
      if (latest.isActive && mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => TeamBattleScreen(challenge: latest)));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('참가 취소'),
        content: const Text('참가를 취소하면 예치한 코인이 환불돼요. 정말 취소할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('닫기', style: TextStyle(color: BC.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('참가 취소', style: TextStyle(color: Color(0xFFE5484D))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _leaving = true);
    try {
      await ParticipantService.cancel(_challenge.id);
      if (!mounted) return;
      showBoosterToast(context, '참가를 취소했어요.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
      setState(() => _leaving = false);
    }
  }

  /// 방장이 자기 방을 없앤다 — 참가자 전원에게 예치금이 돌아가고 방이 닫힌다.
  ///
  /// 방장이 그냥 빠지면 시작시킬 사람이 없는 방에 남의 예치금만 묶인다. 그래서
  /// 방장에게는 "참가 취소" 대신 이 동작을 준다. 모집 중일 때만 가능하다.
  Future<void> _disband() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('챌린지 없애기'),
        content: const Text(
            '참가자 모두에게 예치금이 돌아가고 방이 사라져요. 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('닫기', style: TextStyle(color: BC.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('없애기', style: TextStyle(color: Color(0xFFE5484D))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _leaving = true);
    try {
      await ChallengeService.cancel(_challenge.id);
      if (!mounted) return;
      showBoosterToast(context, '챌린지를 없앴어요. 예치금은 모두 환불했어요.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
      setState(() => _leaving = false);
    }
  }

  /// 승인 화면으로. 방장이 아니면 이 자리가 아예 안 그려진다.
  ///
  /// 승인 없이는 정원이 안 차고, 정원이 안 차면 서버가 팀을 편성하지 않아
  /// 챌린지가 시작조차 못 한다 — 방장이 이 버튼을 못 찾으면 챌린지가 멈춘다.
  Future<void> _goApproval() async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => TeamApprovalScreen(challenge: _challenge)));
    if (changed == true && mounted) _refresh();
  }

  Widget _approvalEntry() {
    return GestureDetector(
      onTap: _goApproval,
      behavior: HitTestBehavior.opaque,
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(color: BC.oSoft, shape: BoxShape.circle),
              child: const Icon(Icons.how_to_reg_rounded, size: 21, color: BC.oMain),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('참가 승인',
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                  SizedBox(height: 2),
                  Text('신청한 사람을 승인해야 인원에 반영돼요',
                      style: TextStyle(fontSize: 12.5, color: BC.ink3)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: BC.ink3),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _challenge.confirmedCount ?? 0;
    final capacity = _challenge.maxParticipants;
    final remaining = (capacity - confirmed).clamp(0, capacity);

    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        child: Column(
          children: [
            BackAppBar(title: _challenge.title, trailing: const CoinPill()),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: BC.oMain,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  children: [
                    _statusHero(confirmed, capacity, remaining),
                    if (_isOwner && _challenge.needsLeaderApproval) ...[
                      const SizedBox(height: 16),
                      _approvalEntry(),
                    ],
                    const SizedBox(height: 16),
                    _infoCard(),
                    if (_challenge.inviteCode != null &&
                        _challenge.inviteCode!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _inviteCard(_challenge.inviteCode!),
                    ],
                    const SizedBox(height: 16),
                    NoteBox(
                      icon: Icons.info_outline_rounded,
                      child: Text(
                        _challenge.needsLeaderApproval
                            ? '방장이 참가 신청을 승인하면 인원에 반영돼요. 정원이 차면 서버가 팀을 편성하고 챌린지를 시작해요.'
                            : '신청하면 바로 참가가 확정돼요. 정원이 차면 서버가 팀을 편성하고 챌린지를 시작해요.',
                        style: const TextStyle(fontSize: 13, color: BC.ink2, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Column(
                children: [
                  PrimaryButton(
                    label: _refreshing ? '새로고침 중...' : '모집 현황 새로고침',
                    leadingIcon: Icons.refresh_rounded,
                    enabled: !_refreshing,
                    onTap: _refresh,
                  ),
                  const SizedBox(height: 8),
                  // 방장에게는 "참가 취소"가 아니라 "방 없애기"를 준다. 자기만
                  // 빠지면 방장 없는 방이 남으므로, 전원 환불 후 방을 닫는다.
                  GestureDetector(
                    onTap: _leaving ? null : (_isOwner ? _disband : _leave),
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      child: Text(
                          _leaving
                              ? '처리하는 중...'
                              : (_isOwner ? '챌린지 없애기' : '참가 취소하기'),
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFE5484D))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusHero(int confirmed, int capacity, int remaining) {
    final progress = capacity == 0 ? 0.0 : (confirmed / capacity).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        gradient: BC.heroGrad,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: BC.o2.withValues(alpha: .32), blurRadius: 26, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .22),
                borderRadius: BorderRadius.circular(999)),
            child: Text(_challenge.isReady ? '팀원 모집 중' : '종료된 챌린지',
                style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 16),
          Text('$confirmed / $capacity명',
              style: const TextStyle(
                  color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(remaining == 0 ? '정원이 모두 찼어요!' : '$remaining명 더 모이면 시작돼요',
              style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: .28),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            alignment: WrapAlignment.center,
            children: [
              for (int i = 0; i < confirmed; i++)
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .9), shape: BoxShape.circle),
                  child: const Icon(Icons.person_rounded, size: 17, color: BC.oMain),
                ),
              for (int i = 0; i < remaining; i++)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white54, width: 1.5)),
                  child: const Icon(Icons.add_rounded, size: 15, color: Colors.white54),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoCard() {
    return AppCard(
      child: Column(
        children: [
          _infoRow(Icons.category_rounded, '카테고리',
              ChallengeCategory.labelOf(_challenge.category)),
          const Divider(height: 22, color: BC.line),
          _infoRow(Icons.calendar_today_rounded, '기간', '${_challenge.durationDays}일'),
          const Divider(height: 22, color: BC.line),
          _infoRow(Icons.savings_rounded, '예치코인',
              '${CoinPill.format(_challenge.depositCoins)} 코인'),
          const Divider(height: 22, color: BC.line),
          _infoRow(Icons.how_to_reg_rounded, '승인 방식',
              _challenge.needsLeaderApproval ? '방장 승인' : '자동 승인'),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: BC.ink3),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 14, color: BC.ink2)),
        const Spacer(),
        Text(value,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _inviteCard(String code) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration:
                BoxDecoration(color: BC.oSoft, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.lock_rounded, size: 21, color: BC.oMain),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('초대 코드', style: TextStyle(fontSize: 12.5, color: BC.ink3)),
                Text(code,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 2)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              showBoosterToast(context, '초대 코드를 복사했어요.');
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Icon(Icons.copy_rounded, size: 20, color: BC.oMain),
            ),
          ),
        ],
      ),
    );
  }
}
