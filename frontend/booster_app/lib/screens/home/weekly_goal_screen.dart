import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../models/weekly_goal.dart';
import '../../services/personal_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';

/// 주간 목표 — A축의 핵심인데 볼 방법이 없던 화면.
///
/// 서버는 "주 N회"를 기준으로 채점하고, 못 채우면 구제권을 소모하거나 스트릭 0 +
/// 코인 −500으로 확정한다. 그런데 앱에 이 목표를 보여주는 자리가 없어서
/// 사용자는 **자기가 무엇을 채워야 하는지 모른 채** 채점당하고 있었다.
///
/// ## 반영 시점이 둘로 갈린다
/// - **목표 횟수**는 예약제다. 바꿔도 이번 주가 아니라 **다음 달 1일**부터
///   적용되고, 그 사실은 응답의 `pendingTargetDays`로만 확인된다. 안내하지
///   않으면 사용자는 바꿔놓고 안 바뀌었다고 여겨 계속 다시 누른다.
/// - **인증 방식**은 즉시 반영된다.
///
/// 같은 화면에서 저장하는 두 값의 반영 시점이 다르다는 걸 화면이 말해줘야 한다.
class WeeklyGoalScreen extends StatefulWidget {
  const WeeklyGoalScreen({super.key});

  @override
  State<WeeklyGoalScreen> createState() => _WeeklyGoalScreenState();
}

class _WeeklyGoalScreenState extends State<WeeklyGoalScreen> {
  /// 서버가 받는 값. 그 외는 400 `UNSUPPORTED_VERIFICATION_TYPE`.
  static const _verificationTypes = <(String, String, String)>[
    ('GPS', '위치', '등록한 장소 반경 안에서 인증해요'),
    ('AI', '사진', 'GPS를 안 봐요. 사진으로만 판정해요'),
    ('GPS_PHOTO_AI', '위치 + 사진', 'GPS를 통과한 뒤 사진으로 확정해요'),
  ];

  bool _loading = true;
  bool _saving = false;

  WeeklyGoal? _goal;

  /// 못 읽은 이유. null인데 [_goal]도 null이면 위치 미등록이다.
  String? _error;

  /// 사용자가 고른 값. 저장 전까지는 서버 값과 다를 수 있다.
  int? _targetDays;
  String? _verificationType;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final goal = await PersonalService.fetchWeeklyGoal();
      if (!mounted) return;
      setState(() {
        _goal = goal;
        _error = null;
        // 예약이 걸려 있으면 그 값을 보여준다 — 사용자가 마지막으로 고른 값이다.
        _targetDays = goal?.pendingTargetDays ?? goal?.targetDays;
        _verificationType = goal?.verificationType;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _dirty {
    final goal = _goal;
    if (goal == null) return false;
    final savedTarget = goal.pendingTargetDays ?? goal.targetDays;
    return _targetDays != savedTarget || _verificationType != goal.verificationType;
  }

  Future<void> _save() async {
    final targetDays = _targetDays;
    if (_saving || targetDays == null) return;

    setState(() => _saving = true);
    try {
      final updated = await PersonalService.updateWeeklyGoal(
        targetDays: targetDays,
        verificationType: _verificationType,
      );
      if (!mounted) return;
      setState(() {
        _goal = updated;
        _targetDays = updated.pendingTargetDays ?? updated.targetDays;
        _verificationType = updated.verificationType;
      });
      // 목표는 예약, 인증 방식은 즉시다. 무엇이 언제 반영됐는지 다르게 말한다.
      showBoosterToast(
        context,
        updated.pendingTargetDays != null
            ? '저장했어요 · 목표는 다음 달 1일부터 주 ${updated.pendingTargetDays}회'
            : '저장했어요',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = _goal;
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        child: Column(
          children: [
            const BackAppBar(title: '주간 목표'),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: BC.oMain))
                  : (goal == null
                      ? _unavailable()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: BC.oMain,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                            children: [
                              _progressCard(goal),
                              const SizedBox(height: 16),
                              _targetCard(goal),
                              const SizedBox(height: 16),
                              _verificationCard(),
                              const SizedBox(height: 16),
                              _ticketCard(goal),
                            ],
                          ),
                        )),
            ),
            if (goal != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                child: PrimaryButton(
                  label: _saving ? '저장하는 중…' : '저장',
                  enabled: !_saving && _dirty,
                  onTap: _save,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 위치 미등록이거나 조회 실패. 둘을 구분해 안내한다 — 전자는 사용자가 할 일이
  /// 있고, 후자는 다시 시도하면 되는 일이다.
  Widget _unavailable() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 16),
      children: [
        Icon(_error == null ? Icons.place_outlined : Icons.cloud_off_rounded,
            size: 34, color: BC.ink3),
        const SizedBox(height: 12),
        Text(
          _error ?? '인증 장소를 등록하면 주간 목표를 정할 수 있어요',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: BC.ink2, height: 1.5),
        ),
      ],
    );
  }

  Widget _progressCard(WeeklyGoal goal) {
    final target = goal.targetDays == 0 ? 1 : goal.targetDays;
    final progress = (goal.successCount / target).clamp(0.0, 1.0);
    final start = goal.weekStart;
    final end = start?.add(const Duration(days: 6));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('이번 주',
                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              if (start != null && end != null)
                MiniTag('${_date(start)}~${_date(end)}'),
              const Spacer(),
              Text('${goal.remainingDays}일 남음',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700, color: BC.oMain)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${goal.successCount}',
                  style: const TextStyle(
                      fontSize: 34, fontWeight: FontWeight.w900, color: BC.oMain)),
              Text(' / ${goal.targetDays} 회',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: BC.ink2)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: BC.line,
              valueColor: const AlwaysStoppedAnimation(BC.oMain),
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetCard(WeeklyGoal goal) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('주간 목표',
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('일주일에 몇 번 인증할까요? (2~7회)',
              style: TextStyle(fontSize: 13, color: BC.ink2)),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var days = 2; days <= 7; days++) ...[
                if (days > 2) const SizedBox(width: 6),
                Expanded(
                  child: SelectChip(
                    label: '$days',
                    selected: _targetDays == days,
                    onTap: () => setState(() => _targetDays = days),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          NoteBox(
            icon: Icons.event_repeat_rounded,
            child: Text(
              goal.pendingTargetDays != null
                  ? '다음 달 1일부터 주 ${goal.pendingTargetDays}회로 바뀌어요. 이번 달은 주 ${goal.targetDays}회예요.'
                  : '목표를 바꾸면 다음 달 1일부터 적용돼요. 이번 주 채점 기준은 그대로 주 ${goal.targetDays}회예요.',
              style: const TextStyle(fontSize: 12.5, color: BC.ink2, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _verificationCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('인증 방식',
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('저장하면 바로 반영돼요.',
              style: TextStyle(fontSize: 13, color: BC.ink2)),
          const SizedBox(height: 14),
          for (final (value, label, description) in _verificationTypes) ...[
            if (value != _verificationTypes.first.$1) const SizedBox(height: 10),
            _verificationOption(value, label, description),
          ],
        ],
      ),
    );
  }

  Widget _verificationOption(String value, String label, String description) {
    final on = _verificationType == value;
    return GestureDetector(
      onTap: () => setState(() => _verificationType = value),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: on ? BC.oSoft : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? BC.oMain : BC.line, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: on ? BC.oMain : BC.ink)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: const TextStyle(fontSize: 12, color: BC.ink3, height: 1.4)),
                ],
              ),
            ),
            Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: on ? BC.oMain : BC.ink3, size: 22),
          ],
        ),
      ),
    );
  }

  /// 구제권 현황. 무료분과 구매분은 소멸 규칙이 달라서 나눠 보여준다.
  Widget _ticketCard(WeeklyGoal goal) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('구제권',
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('목표를 못 채운 주에 자동으로 1개 쓰여요.',
              style: TextStyle(fontSize: 13, color: BC.ink2)),
          const SizedBox(height: 14),
          _ticketRow('무료', goal.freeTickets, '이번 달 말 소멸'),
          const SizedBox(height: 10),
          _ticketRow('구매', goal.paidTickets, '소멸 없음'),
        ],
      ),
    );
  }

  Widget _ticketRow(String label, int count, String note) {
    final has = count > 0;
    return Row(
      children: [
        Icon(Icons.confirmation_num_rounded,
            size: 18, color: has ? BC.oMain : BC.ink3),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: has ? BC.ink : BC.ink3)),
        const SizedBox(width: 8),
        Text('$count개',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: has ? BC.oMain : BC.ink3)),
        const Spacer(),
        Text(note, style: const TextStyle(fontSize: 11.5, color: BC.ink3)),
      ],
    );
  }

  static String _date(DateTime d) => '${d.month}/${d.day}';
}
