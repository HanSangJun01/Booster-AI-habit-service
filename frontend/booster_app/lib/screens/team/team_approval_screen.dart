import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../models/challenge.dart';
import '../../models/participant.dart';
import '../../services/participant_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';

/// 방장 승인 — `approvalType`이 `LEADER`인 챌린지의 대기자 처리.
///
/// ## 이 화면이 없으면 LEADER 챌린지가 작동하지 않는다
/// 자동 승인(`AUTO`)이 아닌 챌린지는 신청자가 `PENDING`으로 멈춰 있고, 방장이
/// 승인해야 `CONFIRMED`가 된다. 승인할 방법이 없으면 정원이 영영 안 차고,
/// 정원이 안 차면 서버가 팀을 편성하지 않으니 챌린지가 시작조차 못 한다.
///
/// ## participantId를 여기서만 얻을 수 있다
/// 승인 API가 요구하는 `participantId`는 참가 신청 응답에 들어 있는데, 그 응답을
/// 받는 건 신청자 본인이지 방장이 아니다. 방장에게는
/// `GET /api/challenges/{id}/participants?status=PENDING`의 `data[].id`가
/// **유일한 획득 경로다.**
class TeamApprovalScreen extends StatefulWidget {
  final Challenge challenge;
  const TeamApprovalScreen({super.key, required this.challenge});

  @override
  State<TeamApprovalScreen> createState() => _TeamApprovalScreenState();
}

class _TeamApprovalScreenState extends State<TeamApprovalScreen> {
  bool _loading = true;
  List<Participant> _pending = const [];

  /// 지금 승인 요청이 나가 있는 participantId. 같은 사람을 두 번 승인하면
  /// 두 번째는 409를 맞는다.
  int? _approving;

  /// 한 명이라도 승인했는지. 돌아갈 때 이전 화면이 다시 읽어야 하는지 알린다.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pending = await ParticipantService.fetchPending(widget.challenge.id);
      if (!mounted) return;
      setState(() => _pending = pending);
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(Participant participant) async {
    if (_approving != null) return;
    setState(() => _approving = participant.id);
    try {
      await ParticipantService.approve(widget.challenge.id, participant.id);
      if (!mounted) return;
      _changed = true;
      showBoosterToast(context, '${participant.displayName}님을 승인했어요');
      // 목록에서 바로 빼지 않고 다시 읽는다 — 그 사이 정원이 찼거나 다른 신청이
      // 들어왔을 수 있고, 그건 서버만 안다.
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
      // 409(이미 승인됨·정원 초과)면 목록이 낡은 것이다. 다시 읽어서 맞춘다.
      if (e.statusCode == 409) await _load();
    } finally {
      if (mounted) setState(() => _approving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: BC.bg,
        body: SafeArea(
          child: Column(
            children: [
              const BackAppBar(title: '참가 승인'),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: BC.oMain))
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: BC.oMain,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          children: [
                            _header(),
                            const SizedBox(height: 14),
                            if (_pending.isEmpty)
                              _emptyBox()
                            else
                              for (final participant in _pending) _pendingCard(participant),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final confirmed = widget.challenge.confirmedCount ?? 0;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.challenge.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.people_alt_rounded, size: 16, color: BC.ink3),
              const SizedBox(width: 6),
              Text('확정 $confirmed / ${widget.challenge.maxParticipants}명',
                  style: const TextStyle(fontSize: 13.5, color: BC.ink2)),
              const Spacer(),
              MiniTag('대기 ${_pending.length}명',
                  bg: _pending.isEmpty ? BC.tagBg : BC.oSoft,
                  fg: _pending.isEmpty ? const Color(0xFF86868B) : BC.oMain),
            ],
          ),
          const SizedBox(height: 12),
          const NoteBox(
            icon: Icons.info_outline_rounded,
            child: Text(
              '승인해야 참가가 확정돼요. 정원이 차면 서버가 팀을 나눠 대결을 시작해요.',
              style: TextStyle(fontSize: 12.5, color: BC.ink2, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyBox() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 44),
      alignment: Alignment.center,
      child: Column(
        children: const [
          Icon(Icons.how_to_reg_outlined, size: 34, color: BC.ink3),
          SizedBox(height: 10),
          Text('승인을 기다리는 사람이 없어요',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BC.ink2)),
          SizedBox(height: 4),
          Text('새로 신청이 들어오면 여기에 나와요.',
              style: TextStyle(fontSize: 12.5, color: BC.ink3)),
        ],
      ),
    );
  }

  Widget _pendingCard(Participant participant) {
    final statement = participant.personalStatement;
    final busy = _approving == participant.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(color: BC.oSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.person_rounded, size: 21, color: BC.oMain),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(participant.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                ),
                _ApproveButton(
                  label: busy ? '승인 중…' : '승인',
                  // 다른 사람을 승인하는 동안에도 잠근다 — 연달아 누르면 정원이
                  // 넘치는 순서로 요청이 나갈 수 있다.
                  enabled: _approving == null,
                  onTap: () => _approve(participant),
                ),
              ],
            ),
            if (statement != null && statement.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration:
                    BoxDecoration(color: BC.bg, borderRadius: BorderRadius.circular(12)),
                child: Text(statement,
                    style: const TextStyle(fontSize: 13, color: BC.ink2, height: 1.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ApproveButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _ApproveButton({required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          gradient: enabled ? BC.grad : null,
          color: enabled ? null : const Color(0xFFE7E6E3),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: enabled ? Colors.white : BC.ink3,
            )),
      ),
    );
  }
}
