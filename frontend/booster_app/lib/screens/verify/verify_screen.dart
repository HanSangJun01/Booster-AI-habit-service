import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/location.dart';
import '../../core/session.dart';
import '../../models/challenge.dart';
import '../../models/challenge_category.dart';
import '../../models/check_in.dart';
import '../../models/personal_location.dart';
import '../../services/challenge_service.dart';
import '../../services/personal_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../home/personal_create_screen.dart';
import '../main_scaffold.dart';
import 'photo_verify_sheet.dart';

/// 인증 화면. 두 갈래가 있다:
/// - 개인 습관 인증 — `POST /api/personal/check-in`
/// - 팀 챌린지 인증 — `POST /api/challenges/{challengeId}/check-ins`
///
/// 둘 다 체크인 생성과 GPS 판정이 **한 번의 호출**로 끝난다. 예전 스펙의
/// "체크인 생성 → 인증 제출" 2단계 구조는 백엔드에 존재하지 않는다.
///
/// 복귀 미션은 폐지됐다 — 백엔드에서 `RecoveryController`가 통째로 사라지고
/// 주간 목표 채점으로 대체됐다. 놓친 날을 그날그날 만회하는 흐름이 없어졌다.
class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});
  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  bool _loading = true;
  TodayStatus? _today;
  PersonalLocation? _location;

  /// 지금 인증할 팀 챌린지. 팀 탭이 `GET /api/users/me/challenges`로 목록을
  /// 복원하면서 [Session.currentChallengeId]를 채워주므로, 앱을 재시작해도
  /// 남아 있다.
  Challenge? _challenge;
  List<CheckIn> _challengeCheckIns = [];

  /// 사진이 남은 개인 체크인의 id.
  ///
  /// ⚠️ `GET /api/personal/check-in/today`는 `checkInId`를 주지 않는다(계약상
  /// date·status·verifiedAt뿐). 그래서 이 값은 **이번 세션에서 체크인한 경우에만**
  /// 알 수 있고, 앱을 껐다 켜면 PENDING인 걸 알면서도 이어서 올릴 수 없다.
  /// 서버가 today 응답에 id를 실어주면 [TodayStatus.checkInId]로 자동으로 메워진다.
  int? _personalCheckInId;

  /// 사진이 남은 개인 체크인 id. 서버가 주면 그 값을, 아니면 이번 세션 값을 쓴다.
  int? get _pendingPhotoCheckInId => _today?.checkInId ?? _personalCheckInId;

  /// 오늘 팀 인증에 사진이 남았는지. 목록에서 PENDING 제출물을 찾는다.
  ///
  /// 개인과 달리 팀은 목록 응답에 `submissionId`가 들어 있어서, 앱을 다시 켜도
  /// 이어서 올릴 수 있다.
  int? get _pendingTeamSubmissionId {
    for (final checkIn in _todayTeamCheckIns) {
      if (checkIn.awaitsPhoto && checkIn.submissionId != null) {
        return checkIn.submissionId;
      }
    }
    return null;
  }

  Iterable<CheckIn> get _todayTeamCheckIns {
    final today = DateTime.now();
    return _challengeCheckIns.where((c) {
      final date = c.checkInDate;
      return date != null &&
          date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
    });
  }

  bool _didInitialLoad = false;
  int? _lastActiveTabIndex;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MainScaffold가 탭을 IndexedStack으로 유지해서 initState가 다시 안 불린다.
    // 인증 탭(index 2)이 새로 활성화될 때마다 최신 상태를 다시 읽는다.
    const verifyTabIndex = 2;
    final current = MainNavScope.of(context).current;
    if (_didInitialLoad && current == verifyTabIndex && _lastActiveTabIndex != verifyTabIndex) {
      _load();
    }
    _lastActiveTabIndex = current;
    _didInitialLoad = true;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        PersonalService.fetchToday(),
        PersonalService.fetchLocation(),
      ]);
      Challenge? challenge;
      var challengeCheckIns = <CheckIn>[];
      final challengeId = Session.currentChallengeId;
      if (challengeId != null) {
        challenge = await ChallengeService.fetchDetail(challengeId);
        challengeCheckIns = await ChallengeService.fetchCheckIns(challengeId);
      }
      if (!mounted) return;
      setState(() {
        _today = results[0] as TodayStatus;
        _location = results[1] as PersonalLocation?;
        _challenge = challenge;
        _challengeCheckIns = challengeCheckIns;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
    } finally {
      // 어떤 예외로 빠져나가든 스피너는 반드시 걷는다. 안 그러면 이 탭이
      // 앱 재시작 전까지 죽는다.
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 팀 챌린지에서 내가 오늘 인증했는지. 서버가 팀 전체 체크인을 주므로
  /// 내 참가자 기록만 골라야 하는데, 참가자 id를 앱이 들고 있지 않아
  /// 오늘 날짜의 성공 기록 존재 여부로 판단한다.
  bool get _teamDoneToday => _todayTeamCheckIns.any((c) => c.isSuccess);

  // ───────────────────────── 인증 실행 ─────────────────────────

  /// 개인 습관 인증.
  ///
  /// 인증 방식이 AI 계열이면 GPS 단계가 `PENDING`으로 끝나고 사진이 남는다.
  /// 거기서 멈추면 PENDING이 하루를 점유해 스트릭도 코인도 오르지 않으므로,
  /// 곧바로 사진 단계로 이어준다.
  Future<void> _startPersonalVerify() async {
    if (_location == null) {
      await _promptLocationSetup();
      return;
    }

    int? pendingCheckInId;
    final passed = await _runVerifySheet((latitude, longitude) async {
      final result = await PersonalService.checkIn(
        latitude: latitude,
        longitude: longitude,
      );
      if (result.awaitsPhoto) pendingCheckInId = result.checkInId;
      // 사진이 남았어도 GPS 단계는 통과한 것이다. 여기서 실패로 그리면
      // 사용자가 위치를 잘못 잡은 줄 안다.
      return result.isSuccess || result.awaitsPhoto;
    });
    if (passed == null || !mounted) return;

    final checkInId = pendingCheckInId;
    if (checkInId != null) {
      _personalCheckInId = checkInId;
      await _uploadPersonalPhoto(checkInId);
      if (!mounted) return;
    }
    await _load();
  }

  /// 개인 사진 인증. GPS 단계 직후에도, 남아 있는 PENDING을 이어서 할 때도 쓴다.
  Future<void> _uploadPersonalPhoto(int checkInId) async {
    await showPhotoVerifySheet(
      context,
      request: PhotoVerifyRequest(
        subtitle: '오늘의 습관을 찍어서 올려주세요.',
        // 개인 트랙에는 카테고리를 저장하는 컬럼이 아예 없다. 그래서 서버에서
        // 가져올 수가 없고 사용자가 매번 고른다.
        fixedAiCategory: null,
        upload: (path, bytes, aiCategory) => PersonalService.verifyPhoto(
          checkInId: checkInId,
          filePath: path,
          bytes: bytes,
          aiCategory: aiCategory,
        ),
      ),
    );
    if (mounted) _personalCheckInId = null;
  }

  /// 팀 챌린지 인증.
  Future<void> _startTeamVerify(Challenge challenge) async {
    int? pendingSubmissionId;
    final passed = await _runVerifySheet((latitude, longitude) async {
      final checkIn = await ChallengeService.checkIn(
        challenge.id,
        latitude: latitude,
        longitude: longitude,
      );
      if (checkIn.awaitsPhoto) pendingSubmissionId = checkIn.submissionId;
      return checkIn.isSuccess || checkIn.awaitsPhoto;
    });
    if (passed == null || !mounted) return;

    final submissionId = pendingSubmissionId;
    if (submissionId != null) {
      await _uploadTeamPhoto(challenge, submissionId);
      if (!mounted) return;
    }
    await _load();
  }

  Future<void> _uploadTeamPhoto(Challenge challenge, int submissionId) async {
    // 챌린지의 category를 그대로 넘기면 안 된다 — 자유 문자열이라 ai-service가
    // 모르는 값(WAKE_UP·옛 한글)이 들어 있을 수 있고, 그러면 500이 난다.
    final aiCategory = ChallengeCategory.aiValueOf(challenge.category);
    if (aiCategory == null) {
      showBoosterToast(context, '이 챌린지는 사진 인증을 지원하지 않아요');
      return;
    }
    await showPhotoVerifySheet(
      context,
      request: PhotoVerifyRequest(
        subtitle: '${challenge.title} 인증 사진을 올려주세요.',
        fixedAiCategory: aiCategory,
        upload: (path, bytes, category) => ChallengeService.verifyPhoto(
          submissionId: submissionId,
          filePath: path,
          bytes: bytes,
          aiCategory: category,
        ),
      ),
    );
  }

  Future<bool?> _runVerifySheet(
      Future<bool> Function(double latitude, double longitude) onSubmit) {
    return showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .5),
      builder: (_) => _GpsVerifySheet(onSubmit: onSubmit),
    );
  }

  /// 인증 기준 위치가 없으면 개인 인증 자체가 불가능하다 — 등록 화면으로 보낸다.
  Future<void> _promptLocationSetup() async {
    final created = await Navigator.of(context).push<PersonalLocation>(
        MaterialPageRoute(builder: (_) => const PersonalCreateScreen()));
    if (created != null && mounted) await _load();
  }

  // ───────────────────────── 화면 ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const BoosterHeader(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: BC.oMain))
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: BC.oMain,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        children: [
                          const Text('오늘의 인증',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          const Text('등록한 장소에서 GPS로 인증해 보세요.',
                              style: TextStyle(fontSize: 13.5, color: BC.ink2)),
                          const SizedBox(height: 22),
                          ..._photoPendingBanners(),
                          _sectionTitle(Icons.person_rounded, BC.oMain, BC.oSoft, '개인 습관',
                              _location == null ? '0' : '1'),
                          const SizedBox(height: 12),
                          _personalCard(),
                          const SizedBox(height: 24),
                          _sectionTitle(Icons.groups_rounded, BC.blue, BC.blueSoft, '팀 챌린지',
                              _challenge == null ? '0' : '1'),
                          const SizedBox(height: 12),
                          _challenge == null
                              ? _noTeamChallenge()
                              : _teamCard(_challenge!),
                        ],
                      ),
                    ),
            ),
            const BoosterBottomNav(),
          ],
        ),
      ),
    );
  }

  /// "사진 인증이 남았어요" 배너들.
  ///
  /// GPS는 통과했는데 사진을 안 올린 상태다. 그냥 두면 PENDING이 하루를 점유해서
  /// 스트릭도 코인도 안 오르는데, 화면에는 아무 표시가 없어 사용자는 인증이 끝난
  /// 줄 안다.
  List<Widget> _photoPendingBanners() {
    final banners = <Widget>[];

    if (_today?.awaitsPhoto == true) {
      final checkInId = _pendingPhotoCheckInId;
      banners.add(_photoBanner(
        title: '개인 습관 · 사진 인증이 남았어요',
        // id를 모르면 이어서 올릴 수가 없다. 누를 수 없는 버튼을 두느니
        // 무엇이 막혀 있는지 말해준다.
        description: checkInId == null
            ? 'GPS는 통과했어요. 앱을 다시 켜서 이어 올리는 건 아직 안 돼요 — 오늘 안에 다시 인증해주세요.'
            : 'GPS는 통과했어요. 사진을 올리면 인증이 확정돼요.',
        onTap: checkInId == null ? null : () => _uploadAndReload(checkInId),
      ));
    }

    final submissionId = _pendingTeamSubmissionId;
    final challenge = _challenge;
    if (submissionId != null && challenge != null) {
      banners.add(_photoBanner(
        title: '팀 챌린지 · 사진 인증이 남았어요',
        description: 'GPS는 통과했어요. 사진을 올리면 인증이 확정돼요.',
        onTap: () async {
          await _uploadTeamPhoto(challenge, submissionId);
          if (mounted) await _load();
        },
      ));
    }

    if (banners.isEmpty) return const [];
    return [
      for (final banner in banners) ...[banner, const SizedBox(height: 12)],
      const SizedBox(height: 10),
    ];
  }

  Future<void> _uploadAndReload(int checkInId) async {
    await _uploadPersonalPhoto(checkInId);
    if (mounted) await _load();
  }

  Widget _photoBanner({
    required String title,
    required String description,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: BC.oSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BC.oSoft2, width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.photo_camera_rounded, size: 22, color: BC.oMain),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800, color: BC.oMain)),
                  const SizedBox(height: 3),
                  Text(description,
                      style: const TextStyle(
                          fontSize: 12.5, color: BC.ink2, height: 1.4)),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right_rounded, color: BC.oMain),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(IconData icon, Color fg, Color bg, String title, String count) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 18, color: fg),
        ),
        const SizedBox(width: 9),
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Text(count,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
        ),
      ],
    );
  }

  Widget _personalCard() {
    if (_location == null) {
      return AppCard(
        child: Column(
          children: [
            const Icon(Icons.place_outlined, size: 32, color: BC.ink3),
            const SizedBox(height: 8),
            const Text('인증 장소가 없어요',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: BC.ink2)),
            const SizedBox(height: 4),
            const Text('장소를 등록해야 GPS 인증을 할 수 있어요.',
                style: TextStyle(fontSize: 12.5, color: BC.ink3)),
            const SizedBox(height: 14),
            PrimaryButton(
              label: '인증 장소 등록하기',
              leadingIcon: Icons.place_rounded,
              onTap: _promptLocationSetup,
            ),
          ],
        ),
      );
    }

    final location = _location!;
    final done = _today?.isDone ?? false;
    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 5, color: BC.oMain),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(location.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w800)),
                          ),
                          _statusPill(done),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                            color: BC.oSoft, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on_rounded, size: 14, color: BC.oMain),
                            const SizedBox(width: 4),
                            Text('반경 ${location.radiusMeters}m 안에서 인증',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: BC.oMain)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      done
                          ? _doneButton()
                          : PrimaryButton(
                              label: '인증하기',
                              leadingIcon: Icons.location_on_rounded,
                              onTap: _startPersonalVerify,
                            ),
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

  Widget _noTeamChallenge() {
    return AppCard(
      child: Column(
        children: const [
          Icon(Icons.groups_outlined, size: 32, color: BC.ink3),
          SizedBox(height: 8),
          Text('참여 중인 팀 챌린지가 없어요',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: BC.ink2)),
          SizedBox(height: 4),
          Text('팀 탭에서 챌린지를 만들거나 참여해보세요.',
              style: TextStyle(fontSize: 12.5, color: BC.ink3)),
        ],
      ),
    );
  }

  Widget _teamCard(Challenge challenge) {
    final done = _teamDoneToday;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ChallengeCategory.labelOf(challenge.category),
                        style: const TextStyle(fontSize: 13, color: BC.ink3)),
                    Text(challenge.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              _statusPill(done),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 15, color: BC.blue),
              const SizedBox(width: 5),
              Text(
                challenge.currentDay == null
                    ? '시작 전 · 총 ${challenge.durationDays}일'
                    : '${challenge.currentDay}일차 / ${challenge.durationDays}일',
                style: const TextStyle(
                    fontSize: 12.5, color: BC.ink2, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!challenge.isActive)
            Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: BC.bg, borderRadius: BorderRadius.circular(14)),
              child: Text(
                  challenge.isReady ? '아직 시작되지 않았어요' : '종료된 챌린지예요',
                  style: const TextStyle(
                      color: BC.ink3, fontSize: 14.5, fontWeight: FontWeight.w700)),
            )
          else if (done)
            _doneButton()
          else
            GestureDetector(
              onTap: () => _startTeamVerify(challenge),
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: BC.blueSoft, borderRadius: BorderRadius.circular(14)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on_rounded, size: 19, color: BC.blue),
                    SizedBox(width: 7),
                    Text('인증하기',
                        style: TextStyle(
                            color: BC.blue, fontSize: 15, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusPill(bool done) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: done ? BC.greenSoft : const Color(0xFFF1F2F5),
          borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(done ? Icons.check_circle_rounded : Icons.schedule_rounded,
              size: 14, color: done ? BC.green : BC.ink3),
          const SizedBox(width: 5),
          Text(done ? '오늘 인증 완료' : '오늘 인증 미완료',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: done ? BC.green : BC.ink3)),
        ],
      ),
    );
  }

  Widget _doneButton() {
    return Container(
      height: 56,
      alignment: Alignment.center,
      decoration:
          BoxDecoration(color: BC.greenSoft, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.check_circle_rounded, color: BC.green, size: 20),
          SizedBox(width: 8),
          Text('인증 완료',
              style: TextStyle(color: BC.green, fontSize: 17, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// 인증 바텀시트가 지나가는 단계.
enum _VerifyStage {
  /// 기기 GPS 좌표를 받아오는 중.
  locating,

  /// 받은 좌표로 서버에 인증을 제출하는 중.
  submitting,

  /// 서버 판정 = 성공.
  passed,

  /// 서버 판정 = 실패(반경 밖 등).
  failed,

  /// 위치를 못 받았거나 서버 요청이 실패해서 판정까지 못 감.
  error,
}

/// GPS 인증 바텀시트: 기기 위치 탐지 → 서버 제출 → 서버가 준 판정 표시.
///
/// 좌표는 [LocationService]로 실제 기기에서 받고, 성공/실패는 서버 응답
/// 그대로다 — 시트가 자체적으로 성공을 만들어내지 않는다.
///
/// pop 값: 성공 true / 실패 false / 제출까지 못 감 null.
class _GpsVerifySheet extends StatefulWidget {
  /// 실제 기기 좌표를 받아 인증을 제출하고, 서버 판정을 돌려준다.
  final Future<bool> Function(double latitude, double longitude) onSubmit;

  const _GpsVerifySheet({required this.onSubmit});

  @override
  State<_GpsVerifySheet> createState() => _GpsVerifySheetState();
}

class _GpsVerifySheetState extends State<_GpsVerifySheet> with SingleTickerProviderStateMixin {
  _VerifyStage _stage = _VerifyStage.locating;
  late final AnimationController _ctrl;
  double? _latitude;
  double? _longitude;
  String _errorMessage = '';
  bool _needsAppSettings = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _run();
  }

  /// 위치 탐지 → 제출 → 판정. 실패는 전부 error 단계로 모아 사유를 보여준다.
  Future<void> _run() async {
    try {
      final position = await LocationService.current();
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _stage = _VerifyStage.submitting;
      });

      final passed = await widget.onSubmit(position.latitude, position.longitude);
      if (!mounted) return;
      _ctrl.stop();
      setState(() => _stage = passed ? _VerifyStage.passed : _VerifyStage.failed);
    } on LocationException catch (e) {
      _fail(e.message, needsAppSettings: e.needsAppSettings);
    } on ApiException catch (e) {
      _fail(e.message);
    } catch (_) {
      // 시트는 결과가 나올 때까지 닫히지 않으므로, 예상 못 한 예외(응답 형식이
      // 계약과 다를 때의 캐스팅 오류 등)까지 반드시 여기서 받아야 한다.
      // 안 그러면 "인증 처리 중…"에서 영영 멈춘다.
      _fail('인증을 처리하지 못했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  void _fail(String message, {bool needsAppSettings = false}) {
    if (!mounted) return;
    _ctrl.stop();
    setState(() {
      _errorMessage = message;
      _needsAppSettings = needsAppSettings;
      _stage = _VerifyStage.error;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _title {
    switch (_stage) {
      case _VerifyStage.locating:
        return '위치를 탐지하고 있어요';
      case _VerifyStage.submitting:
        return '등록한 장소와 맞춰보는 중';
      case _VerifyStage.passed:
        return '인증 완료!';
      case _VerifyStage.failed:
        return '인증 반경을 벗어났어요';
      case _VerifyStage.error:
        return '인증을 진행할 수 없어요';
    }
  }

  String get _subtitle {
    switch (_stage) {
      case _VerifyStage.locating:
        return 'GPS 신호를 받아오는 중이에요…';
      case _VerifyStage.submitting:
        final lat = _latitude;
        final lng = _longitude;
        return lat == null || lng == null
            ? '위치를 확인했어요'
            : '위도 ${lat.toStringAsFixed(5)}, 경도 ${lng.toStringAsFixed(5)}';
      case _VerifyStage.passed:
        return '오늘의 인증이 기록됐어요';
      case _VerifyStage.failed:
        return '등록한 장소 근처에서 다시 시도해주세요';
      case _VerifyStage.error:
        return _errorMessage;
    }
  }

  @override
  Widget build(BuildContext context) {
    final inProgress =
        _stage == _VerifyStage.locating || _stage == _VerifyStage.submitting;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding:
          EdgeInsets.fromLTRB(24, 16, 24, 28 + MediaQuery.of(context).padding.bottom),
      // 고정 간격 합계(그래픽 150 + 여백 30/26/28 + 버튼)에 안내 문구가 두 줄이
      // 되면 작은 화면에서 몇 px씩 넘친다. 스크롤 가능하게 두면 문구 길이나
      // 화면 크기와 무관하게 안전하다.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration:
                  BoxDecoration(color: BC.line, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(height: 30),
            SizedBox(height: 150, child: _graphic(inProgress)),
            const SizedBox(height: 26),
            Text(_title,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(_subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: BC.ink2)),
            const SizedBox(height: 28),
            _action(inProgress),
          ],
        ),
      ),
    );
  }

  Widget _graphic(bool inProgress) {
    if (inProgress) return _radar();
    if (_stage == _VerifyStage.passed) return _success();
    return _problem();
  }

  Widget _action(bool inProgress) {
    if (inProgress) {
      return Container(
        height: 56,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: BC.bg, borderRadius: BorderRadius.circular(16)),
        child: const Text('인증 처리 중…',
            style:
                TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BC.ink3)),
      );
    }
    if (_stage == _VerifyStage.error && _needsAppSettings) {
      return Column(
        children: [
          PrimaryButton(
            label: '설정 열기',
            onTap: () async {
              await LocationService.openAppSettings();
              if (mounted) Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              child: const Text('닫기',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: BC.ink3)),
            ),
          ),
        ],
      );
    }
    // passed → true, failed → false, error → null(제출 결과 없음).
    final result = switch (_stage) {
      _VerifyStage.passed => true,
      _VerifyStage.failed => false,
      _ => null,
    };
    return PrimaryButton(
      label: _stage == _VerifyStage.error ? '닫기' : '확인',
      onTap: () => Navigator.of(context).pop(result),
    );
  }

  Widget _radar() {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Stack(
          alignment: Alignment.center,
          children: [
            for (int i = 0; i < 3; i++) _ring((_ctrl.value + i / 3) % 1.0),
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(gradient: BC.grad, shape: BoxShape.circle),
              child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 30),
            ),
          ],
        );
      },
    );
  }

  Widget _ring(double t) {
    final size = 56 + t * 90;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: BC.oMain.withValues(alpha: (1 - t) * 0.5), width: 2),
      ),
    );
  }

  Widget _success() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      builder: (_, v, __) => Transform.scale(
        scale: v,
        child: Container(
          width: 110,
          height: 110,
          decoration: const BoxDecoration(color: BC.greenSoft, shape: BoxShape.circle),
          child: Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(color: BC.green, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 44),
            ),
          ),
        ),
      ),
    );
  }

  Widget _problem() {
    final failed = _stage == _VerifyStage.failed;
    return Center(
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
            color: failed ? BC.oSoft : const Color(0xFFF1F2F5), shape: BoxShape.circle),
        child: Icon(
          failed ? Icons.location_off_rounded : Icons.error_outline_rounded,
          size: 52,
          color: failed ? BC.oMain : BC.ink3,
        ),
      ),
    );
  }
}
