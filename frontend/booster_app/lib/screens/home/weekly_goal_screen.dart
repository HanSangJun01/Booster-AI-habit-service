import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../models/challenge_category.dart';
import '../../models/personal_location.dart';
import '../../models/weekly_goal.dart';
import '../../services/personal_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import 'personal_create_screen.dart';

/// 내 습관 설정 — 목표 횟수·카테고리·인증 장소를 한 자리에서 다룬다.
///
/// 예전엔 "주간 목표"였고 장소는 다른 화면에 있었다. 목표와 장소는 같은 주기로
/// 바뀌는 한 세트라(둘 다 다음 달 1일 반영) 따로 두면 사용자가 규칙을 알 수 없다.
///
/// 서버는 "주 N회"를 기준으로 채점하고, 못 채우면 구제권을 소모하거나 스트릭 0 +
/// 코인 −500으로 확정한다. 그런데 앱에 이 목표를 보여주는 자리가 없어서
/// 사용자는 **자기가 무엇을 채워야 하는지 모른 채** 채점당하고 있었다.
///
/// ## 반영 시점이 둘로 갈린다
/// - **목표 횟수**는 예약제다. 바꿔도 이번 주가 아니라 **다음 달 1일**부터
///   적용되고, 그 사실은 응답의 `pendingTargetDays`로만 확인된다. 안내하지
///   않으면 사용자는 바꿔놓고 안 바뀌었다고 여겨 계속 다시 누른다.
/// - **인증 장소**도 예약제다. 목표 횟수와 한 세트로 다음 달 1일에 함께 바뀐다 —
///   아무 때나 옮길 수 있으면 인증 직전에 지금 자리로 바꿔 어디서든 통과할 수 있다.
/// - **카테고리**(운동/공부)는 즉시 반영된다. 바꿔도 이번 주 채점 기준이 흔들리지 않는다.
/// - **인증 방식**은 "위치 + 사진" 하나로 고정이라 고를 수 없다.
///
/// 같은 화면에서 저장하는 두 값의 반영 시점이 다르다는 걸 화면이 말해줘야 한다.
class WeeklyGoalScreen extends StatefulWidget {
  const WeeklyGoalScreen({super.key});

  @override
  State<WeeklyGoalScreen> createState() => _WeeklyGoalScreenState();
}

class _WeeklyGoalScreenState extends State<WeeklyGoalScreen> {
  /// 인증 방식은 고를 수 없다 — 위치만·사진만은 각각 우회가 쉬워 "위치 + 사진"
  /// 하나로 정해졌고, 서버도 그 값만 받는다.
  static const _fixedVerificationType = 'GPS_PHOTO_AI';

  bool _loading = true;
  bool _saving = false;

  WeeklyGoal? _goal;

  /// 못 읽은 이유. null인데 [_goal]도 null이면 위치 미등록이다.
  String? _error;

  /// 사용자가 고른 값. 저장 전까지는 서버 값과 다를 수 있다.
  int? _targetDays;
  String? _category;

  /// 인증 장소. 목표와 한 세트로 이 화면에서 함께 다룬다 —
  /// 장소를 아무 때나 바꿀 수 있으면 인증 직전에 지금 자리로 옮겨 통과할 수 있다.
  PersonalLocation? _location;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 목표와 장소를 한 화면에서 다루므로 둘을 같이 읽는다.
      final goal = await PersonalService.fetchWeeklyGoal();
      final location = await PersonalService.fetchLocation();
      if (!mounted) return;
      setState(() {
        _goal = goal;
        _location = location;
        _error = null;
        // 예약이 걸려 있으면 그 값을 보여준다 — 사용자가 마지막으로 고른 값이다.
        _targetDays = goal?.pendingTargetDays ?? goal?.targetDays;
        _category = goal?.category;
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
    return _targetDays != savedTarget || _category != goal.category;
  }

  Future<void> _save() async {
    final targetDays = _targetDays;
    if (_saving || targetDays == null) return;

    setState(() => _saving = true);
    try {
      final updated = await PersonalService.updateWeeklyGoal(
        targetDays: targetDays,
        verificationType: _fixedVerificationType,
        category: _category,
      );
      if (!mounted) return;
      setState(() {
        _goal = updated;
        _targetDays = updated.pendingTargetDays ?? updated.targetDays;
        _category = updated.category;
      });
      // 목표는 예약, 카테고리는 즉시다. 무엇이 언제 반영됐는지 다르게 말한다.
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
            const BackAppBar(title: '내 습관 설정'),
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
                              _categoryCard(),
                              const SizedBox(height: 16),
                              _locationCard(),
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

  /// 목표 카테고리. 무엇을 습관으로 삼는지 — AI 사진 판정의 기준이 된다.
  Widget _categoryCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('무슨 습관인가요',
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('사진 인증을 이 기준으로 판정해요. 저장하면 바로 반영돼요.',
              style: TextStyle(fontSize: 13, color: BC.ink2)),
          const SizedBox(height: 14),
          Row(children: [
            for (final c in ChallengeCategory.choices) ...[
              if (c != ChallengeCategory.choices.first) const SizedBox(width: 7),
              Expanded(
                child: SelectChip(
                  label: c.label,
                  selected: _category == c.value,
                  onTap: () => setState(() => _category = c.value),
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  /// 인증 장소.
  ///
  /// 목표 횟수와 한 세트다 — 아무 때나 바꿀 수 있으면 인증 직전에 지금 있는 자리로
  /// 옮겨 어디서든 통과할 수 있다. 그래서 변경은 다음 달 1일부터 반영된다.
  Widget _locationCard() {
    final location = _location;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('인증 장소',
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('여기 반경 안에서 사진을 올려야 인증돼요.',
              style: TextStyle(fontSize: 13, color: BC.ink2)),
          const SizedBox(height: 14),
          if (location == null)
            const Text('아직 등록하지 않았어요.',
                style: TextStyle(fontSize: 14, color: BC.ink3))
          else ...[
            Row(children: [
              const Icon(Icons.place_rounded, color: BC.oMain, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(location.displayName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              Text('반경 ${location.radiusMeters}m',
                  style: const TextStyle(fontSize: 13, color: BC.ink3)),
            ]),
            // 예약이 걸려 있으면 지금 값과 함께 보여준다. 안 그러면 사용자가
            // "바꿨는데 왜 그대로지?" 하고 계속 다시 누른다.
            if (location.hasPendingChange) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: BC.oSoft, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.schedule_rounded, color: BC.oMain, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '다음 달 1일부터 · ${location.pendingDisplayName}'
                      ' (반경 ${location.pendingRadiusMeters}m)',
                      style: const TextStyle(
                          fontSize: 12.5, color: BC.oMain, fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
              ),
            ],
          ],
          const SizedBox(height: 12),
          _secondaryButton(
              location == null ? '장소 등록하기' : '장소 바꾸기', _openLocationEditor),
          if (location != null) ...[
            const SizedBox(height: 8),
            const Text('바꾼 장소는 다음 달 1일부터 적용돼요.',
                style: TextStyle(fontSize: 12, color: BC.ink3)),
          ],
        ],
      ),
    );
  }

  /// 카드 안에서 쓰는 보조 버튼. 주 동작(저장)과 구분되도록 테두리만 둔다.
  Widget _secondaryButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BC.oMain, width: 1.4),
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w800, color: BC.oMain)),
        ),
      ),
    );
  }

  Future<void> _openLocationEditor() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PersonalCreateScreen(current: _location)));
    if (mounted) _load();
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
