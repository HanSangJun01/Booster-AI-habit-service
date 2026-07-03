import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../models/team.dart';
import '../../services/team_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import 'team_battle_screen.dart';

/// 신청/승인 대기 중인 팀원 한 명.
///
/// 팀 멤버 상세 목록·승인 상태를 반환하는 API가 아직 없어서(§Team 주석 참고)
/// 전부 클라이언트에서만 관리하는 로컬 상태다. 실제 신청자를 만들 방법이
/// 없으므로 디버그 빌드에서 가상 신청자를 추가하는 버튼으로 대신 테스트한다.
class _Member {
  final int userId;
  final String nickname;
  bool approved;
  /// 신청 시 작성하는 소개글(personal statement). API에 신청 메시지를
  /// 저장/조회하는 필드가 아직 없어 목업 데이터로만 채워진다.
  final String? message;
  _Member({
    required this.userId,
    required this.nickname,
    this.approved = true,
    this.message,
  });
}

/// 팀에 참여/생성했지만 아직 정원이 다 안 찬 상태.
///
/// - 참여자 목록과 승인 대기 신청자를 보여준다. 승인/거절/강퇴는 방장(팀
///   생성자, team.ownerId)만 할 수 있고, 방장이 아니면 버튼 자체가 안 보인다.
/// - "챌린지 시작하기"도 방장 전용이며, 정원이 다 찼을 때만 눌린다(자동 시작
///   아님 — 방장이 직접 시작).
/// - 정원/멤버 목록이 API에 없는 클라이언트 전용 값이라, 실제 팀원 입장
///   이벤트를 실시간으로 받을 방법이 없다. "새로고침"으로 수동 재조회하거나,
///   디버그 빌드 전용 테스트 버튼으로 흉내 낼 수 있다.
class TeamWaitingScreen extends StatefulWidget {
  final Team team;
  const TeamWaitingScreen({super.key, required this.team});
  @override
  State<TeamWaitingScreen> createState() => _TeamWaitingScreenState();
}

class _TeamWaitingScreenState extends State<TeamWaitingScreen> {
  late Team _team;
  bool _refreshing = false;
  List<_Member> _members = [];
  int _applicantSeq = 1;

  /// 디버그 빌드에서 방장/일반 유저 시점을 바로 전환해서 미리보기 위한 값.
  /// null이면 실제 소유권(Session.userId == team.ownerId)을 따른다.
  bool? _debugRoleOverride;

  bool get _isOwner {
    if (kDebugMode && _debugRoleOverride != null) return _debugRoleOverride!;
    return Session.userId != null && Session.userId == _team.ownerId;
  }

  @override
  void initState() {
    super.initState();
    _team = widget.team;
    Session.upsertTeam(_team);
    _seedMembers();
  }

  void _seedMembers() {
    _members = [
      _Member(
        userId: Session.userId ?? 0,
        nickname: Session.nickname ?? '나',
        approved: true,
      ),
      for (int i = 1; i < _team.memberCount; i++)
        _Member(userId: -i, nickname: '팀원$i', approved: true),
    ];
  }

  Team _withMemberCount(int count) => Team(
        teamId: _team.teamId,
        name: _team.name,
        description: _team.description,
        ownerId: _team.ownerId,
        memberCount: count,
        capacity: _team.capacity,
        weeklyTarget: _team.weeklyTarget,
        deposit: _team.deposit,
        isPublic: _team.isPublic,
      );

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final teams = await TeamService.fetchMyTeams();
      if (!mounted) return;
      final matches = teams.where((t) => t.teamId == _team.teamId);
      final fresh = matches.isEmpty ? null : matches.first;
      if (fresh != null) {
        setState(() => _team = _withMemberCount(fresh.memberCount));
        Session.upsertTeam(_team);
      }
    } on ApiException catch (_) {
      // 백엔드 미연결 — 새로고침 실패는 무시하고 현재 상태를 유지한다.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _debugFillTeam() {
    final cap = _team.capacity ?? 10;
    setState(() {
      for (int i = _members.where((m) => m.approved).length; i < cap; i++) {
        _members.add(_Member(userId: -100 - i, nickname: '팀원$i', approved: true));
      }
      _team = _withMemberCount(cap);
    });
    Session.upsertTeam(_team);
  }

  static const _mockMessages = [
    '매일 아침 6시에 일어나서 꼭 인증할게요! 작심삼일 탈출이 목표입니다.',
    '작년에 비슷한 챌린지 완주해봤어요. 이번에도 끝까지 함께하고 싶습니다.',
    '운동 습관 만들려고 신청했어요. 열심히 참여하겠습니다!',
  ];

  void _debugAddApplicant() {
    if (_team.isFull) return;
    setState(() {
      _members.add(_Member(
        userId: -1000 - _applicantSeq,
        nickname: '지원자$_applicantSeq',
        approved: false,
        message: _mockMessages[(_applicantSeq - 1) % _mockMessages.length],
      ));
      _applicantSeq++;
    });
  }

  void _approve(_Member m) {
    setState(() {
      m.approved = true;
      _team = _withMemberCount(_team.memberCount + 1);
    });
    Session.upsertTeam(_team);
  }

  void _reject(_Member m) {
    setState(() => _members.remove(m));
  }

  Future<void> _kick(_Member m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('팀원을 강퇴할까요?'),
        content: Text('${m.nickname}님을 팀에서 내보내요. 이 작업은 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소', style: TextStyle(color: BC.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('강퇴', style: TextStyle(color: Color(0xFFE5484D))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TeamService.removeMember(_team.teamId, m.userId);
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
      return;
    }
    if (!mounted) return;
    setState(() {
      _members.remove(m);
      _team = _withMemberCount(_team.memberCount - 1);
    });
    Session.upsertTeam(_team);
  }

  void _startChallenge() {
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TeamBattleScreen(teamName: _team.name)));
  }

  @override
  Widget build(BuildContext context) {
    final cap = _team.capacity ?? 10;
    final cur = _team.memberCount.clamp(0, cap);
    final approvedMembers = _members.where((m) => m.approved).toList();
    final pendingApplicants = _members.where((m) => !m.approved).toList();

    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        child: Column(
          children: [
            const BackAppBar(title: '팀원 모집 중', trailing: CoinPill()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                children: [
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: const BoxDecoration(
                          color: Color(0xFFFDE6DB), shape: BoxShape.circle),
                      child: const Icon(Icons.hourglass_top_rounded,
                          size: 42, color: BC.oMain),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(_team.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    _isOwner
                        ? '정원이 차면 챌린지를 시작할 수 있어요'
                        : '방장이 시작하면 배틀이 시작돼요',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13.5, color: BC.ink2),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF8F7F5),
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text.rich(TextSpan(children: [
                              TextSpan(
                                  text: '$cur',
                                  style: const TextStyle(
                                      color: BC.oMain,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800)),
                              TextSpan(
                                  text: ' / $cap명',
                                  style: const TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w700)),
                            ])),
                            const Spacer(),
                            Text('${cap - cur}명 남음',
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
                            value: cap > 0 ? cur / cap : 0,
                            minHeight: 8,
                            backgroundColor: const Color(0xFFE8E6E2),
                            valueColor: const AlwaysStoppedAnimation(BC.oMain),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('참여자',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: BC.line)),
                    child: Column(
                      children: approvedMembers.map(_memberTile).toList(),
                    ),
                  ),
                  if (pendingApplicants.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('승인 대기 중인 신청자',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: BC.line)),
                      child: Column(
                        children: pendingApplicants.map(_applicantTile).toList(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_isOwner)
                    PrimaryButton(
                      label: '챌린지 시작하기',
                      leadingIcon: Icons.play_arrow_rounded,
                      enabled: _team.isFull,
                      onTap: _startChallenge,
                    ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _refreshing ? null : _refresh,
                    child: Container(
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: BC.line, width: 1.5)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.refresh_rounded, size: 18, color: BC.oMain),
                          const SizedBox(width: 7),
                          Text(_refreshing ? '확인 중...' : '모집 현황 새로고침',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => setState(() => _debugRoleOverride = !_isOwner),
                      child: Container(
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: const Color(0xFFF3E8FF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF9B5DE5), width: 1.2)),
                        child: Text(
                            _isOwner ? '[테스트] 일반 유저 시점으로 보기' : '[테스트] 방장 시점으로 보기',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF9B5DE5))),
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _debugAddApplicant,
                      child: Container(
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: BC.greenSoft,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: BC.green, width: 1.2)),
                        child: const Text('[테스트] 가상 신청자 추가',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700, color: BC.green)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _debugFillTeam,
                      child: Container(
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: BC.blueSoft,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: BC.blue, width: 1.2)),
                        child: const Text('[테스트] 팀원 다 모인 것으로 처리',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700, color: BC.blue)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(_Member m) {
    final isOwnerMember = m.userId == _team.ownerId;
    final canKick = _isOwner && !isOwnerMember;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Color(0xFFF0997B), shape: BoxShape.circle),
            child: Text(m.nickname.isEmpty ? '?' : m.nickname.substring(0, 1),
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(m.nickname,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                if (isOwnerMember) ...[
                  const SizedBox(width: 6),
                  const MiniTag('방장', bg: BC.oSoft, fg: BC.oMain),
                ],
              ],
            ),
          ),
          if (canKick)
            GestureDetector(
              onTap: () => _kick(m),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: BC.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: BC.line)),
                child: const Text('강퇴',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE5484D))),
              ),
            ),
        ],
      ),
    );
  }

  Widget _applicantTile(_Member m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _showApplicantDetail(m),
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFD6D4CF), width: 1.5)),
              child:
                  const Icon(Icons.person_outline_rounded, size: 16, color: Color(0xFFC2C0BB)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.nickname,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  if (m.message != null) ...[
                    const SizedBox(height: 2),
                    Text(m.message!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: BC.ink2)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_isOwner) ...[
              GestureDetector(
                onTap: () => _reject(m),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: BC.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: BC.line)),
                  child: const Text('거절',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: BC.ink2)),
                ),
              ),
              GestureDetector(
                onTap: () => _approve(m),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration:
                      BoxDecoration(color: BC.oMain, borderRadius: BorderRadius.circular(8)),
                  child: const Text('승인',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ] else
              const MiniTag('승인 대기 중'),
          ],
        ),
      ),
    );
  }

  void _showApplicantDetail(_Member m) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(sheetContext).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFD6D4CF), width: 1.5)),
                    child: const Icon(Icons.person_outline_rounded,
                        size: 18, color: Color(0xFFC2C0BB)),
                  ),
                  const SizedBox(width: 12),
                  Text(m.nickname,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 16),
              const Text('소개글',
                  style: TextStyle(fontSize: 12.5, color: BC.ink2, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(m.message?.isNotEmpty == true ? m.message! : '작성한 소개글이 없어요.',
                  style: const TextStyle(fontSize: 14.5, color: BC.ink, height: 1.5)),
              if (_isOwner) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _reject(m);
                        },
                        child: Container(
                          height: 50,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: BC.line, width: 1.5)),
                          child: const Text('거절',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700, color: BC.ink2)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _approve(m);
                        },
                        child: Container(
                          height: 50,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: BC.oMain, borderRadius: BorderRadius.circular(14)),
                          child: const Text('승인',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
