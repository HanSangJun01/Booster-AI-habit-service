import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../models/weekly_goal.dart';
import '../../services/personal_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';

/// 지난주 목표를 못 채웠을 때 뜨는 구제 안내.
///
/// ## 이게 없으면 유예 기능 자체가 무의미해진다
/// 서버는 미달을 즉시 실패시키지 않고 2일짜리 유예(`PENDING_RESCUE`)를 준다.
/// 기한이 지나면 매일 00:10 스케줄러가 확정하면서 **스트릭 0 + 코인 −500**을
/// 가져간다. 앱이 알려주지 않으면 사용자는 그걸 새벽에 예고 없이 맞는다 —
/// 서버가 굳이 유예를 둔 이유가 통째로 사라진다.
///
/// 그래서 조건은 하나다: `GET /api/personal/weekly-goal`의 `pendingRescueWeek`이
/// null이 아니면 띄운다. 기한이 2일뿐이라 놓치면 되돌릴 방법이 없어서, 홈 진입과
/// 앱 포그라운드 복귀 양쪽에서 확인한다.
///
/// 되돌아오는 값은 "홈이 다시 읽어야 하는가"다. 구제에 성공했거나, 서버가 이미
/// 처리했다고(또는 기한이 지났다고) 답한 경우가 여기 해당한다 — 어느 쪽이든
/// 화면에 남은 값이 낡았다는 뜻이다.
Future<bool> showRescueNotice(BuildContext context, WeeklyGoal goal) async {
  final changed = await showDialog<bool>(
    context: context,
    // 닫기 쉬운 팝업으로 두면 "실수로 넘겼다"가 곧 스트릭 0이 된다. 나가는
    // 길은 [나중에] 하나로 좁혀서 최소한 읽고 넘기게 한다.
    barrierDismissible: false,
    builder: (_) => _RescueNoticeDialog(goal: goal),
  );
  return changed ?? false;
}

class _RescueNoticeDialog extends StatefulWidget {
  final WeeklyGoal goal;
  const _RescueNoticeDialog({required this.goal});

  @override
  State<_RescueNoticeDialog> createState() => _RescueNoticeDialogState();
}

class _RescueNoticeDialogState extends State<_RescueNoticeDialog> {
  bool _busy = false;

  /// 구제에 실패한 이유. 다시 시도할 수 있는 경우에만 채운다.
  String? _error;

  Future<void> _rescue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await PersonalService.rescue();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showBoosterToast(context, '구제했어요 · 스트릭이 지켜졌어요');
    } on ApiException catch (e) {
      if (!mounted) return;
      // 이미 처리됐거나 기한이 지난 경우엔 팝업을 열어둘 이유가 없다. 여기서
      // 재시도 버튼을 남겨두면 눌러도 같은 답만 돌아온다.
      if (e.errorCode == 'NO_PENDING_RESCUE' ||
          e.errorCode == 'RESCUE_DEADLINE_PASSED') {
        Navigator.of(context).pop(true);
        showBoosterToast(context, e.message);
        return;
      }
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: BC.oSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.error_outline_rounded, size: 22, color: BC.oMain),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('지난주 목표를 못 채웠어요',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _summary(goal),
            const SizedBox(height: 16),
            _outcome(
              title: '지금 구제하면',
              lines: const ['스트릭 유지 · 코인 차감 없음'],
              bg: BC.greenSoft,
              fg: BC.green,
              icon: Icons.check_circle_rounded,
            ),
            const SizedBox(height: 10),
            _outcome(
              title: '그냥 두면',
              // −500은 주간 미달 확정 페널티(`WEEKLY_MISS_PENALTY`)다. 서버
              // 설정값(`booster.weekly.*`)이라 응답에는 안 실려 온다.
              lines: const ['스트릭 0 · 코인 500 차감'],
              bg: BC.oSoft,
              fg: BC.oMain,
              icon: Icons.warning_amber_rounded,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              NoteBox(
                icon: Icons.info_outline_rounded,
                child: Text(_error!,
                    style: const TextStyle(fontSize: 12.5, color: BC.ink2, height: 1.4)),
              ),
            ],
            const SizedBox(height: 18),
            PrimaryButton(
              label: _busy
                  ? '구제하는 중…'
                  : '${CoinPill.format(goal.lateRescuePrice)}코인으로 구제하기',
              enabled: !_busy,
              onTap: _rescue,
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                child: const Text('나중에',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: BC.ink3)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 어느 주가 걸렸고 언제까지인지.
  ///
  /// 그 주에 몇 번 성공했는지는 보여주지 않는다 — 응답의 `successCount`는
  /// **이번 주** 값이라, 지난주 자리에 갖다 쓰면 틀린 숫자를 단정하게 된다.
  Widget _summary(WeeklyGoal goal) {
    final start = goal.pendingRescueWeek;
    final end = goal.pendingRescueWeekEnd;
    final deadline = goal.rescueDeadline;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: BC.bg, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (start != null && end != null)
            Text('${_date(start)}~${_date(end)}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: BC.ink)),
          const SizedBox(height: 4),
          Text('목표 ${goal.targetDays}회를 채우지 못했어요',
              style: const TextStyle(fontSize: 13, color: BC.ink2)),
          if (deadline != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 15, color: BC.oMain),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${_deadline(deadline)}까지 구제할 수 있어요',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700, color: BC.oMain)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _outcome({
    required String title,
    required List<String> lines,
    required Color bg,
    required Color fg,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
                const SizedBox(height: 2),
                for (final line in lines)
                  Text(line,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700, color: BC.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) => '${d.month}/${d.day}';

  static String _deadline(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.month}월 ${d.day}일 $hh:$mm';
  }
}
