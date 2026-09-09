import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../models/ai_verification.dart';
import '../../models/challenge_category.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';

/// 앱이 고른 사진 한 장.
///
/// `image_picker`의 `XFile`을 그대로 들고 다니지 않는 건 테스트 때문이다 —
/// 플러그인은 테스트 환경에서 동작하지 않아서, 사진을 고르는 행위를 갈아끼울 수
/// 있어야 업로드 이후의 흐름을 검증할 수 있다.
class PickedImage {
  /// 확장자 판별에 쓴다. 서버는 jpg·png·webp만 받는다.
  final String path;
  final Uint8List bytes;

  const PickedImage({required this.path, required this.bytes});
}

/// 사진을 고르는 방법. 실제 구현은 [pickWithImagePicker]다.
typedef ImagePickFn = Future<PickedImage?> Function(ImageSource source);

Future<PickedImage?> pickWithImagePicker(ImageSource source) async {
  // 원본 그대로 올리면 요즘 폰 사진 한 장이 10MB 상한에 쉽게 닿는다. 판정에
  // 필요한 건 무엇이 찍혔는지지 화소 수가 아니라서, 긴 변을 줄여 보낸다.
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 85,
  );
  if (file == null) return null;
  return PickedImage(path: file.path, bytes: await file.readAsBytes());
}

/// 사진 인증 한 건에 필요한 것들.
class PhotoVerifyRequest {
  /// 시트 제목 아래 붙는 설명(무엇을 인증하는지).
  final String subtitle;

  /// 서버로 보낼 카테고리. null이면 사용자가 고른다.
  ///
  /// 팀 챌린지는 챌린지에 저장된 값에서 정해지고, 개인 트랙은 **카테고리를
  /// 저장하는 곳이 서버에 없어서** 올릴 때마다 물어야 한다.
  final String? fixedAiCategory;

  final Future<AiVerificationResult> Function(
    String filePath,
    Uint8List bytes,
    String aiCategory,
  ) upload;

  const PhotoVerifyRequest({
    required this.subtitle,
    required this.fixedAiCategory,
    required this.upload,
  });
}

/// AI 사진 인증 바텀시트.
///
/// GPS 체크인이 `PENDING`으로 끝났을 때 이어지는 두 번째 단계다. 이 단계가
/// 없으면 인증이 PENDING인 채로 하루를 점유하고, 스트릭도 코인도 오르지 않는다.
///
/// 판정에 실패해도 그날이 끝나는 게 아니다 — 서버가 체크인 레코드를 지워서
/// 다시 찍어 올릴 수 있다. 그래서 실패 화면의 기본 행동은 '다시 찍기'다.
Future<AiVerificationResult?> showPhotoVerifySheet(
  BuildContext context, {
  required PhotoVerifyRequest request,
  ImagePickFn pick = pickWithImagePicker,
}) {
  return showModalBottomSheet<AiVerificationResult>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .5),
    builder: (_) => _PhotoVerifySheet(request: request, pick: pick),
  );
}

enum _PhotoStage { choosing, uploading, passed, rejected, error }

class _PhotoVerifySheet extends StatefulWidget {
  final PhotoVerifyRequest request;
  final ImagePickFn pick;

  const _PhotoVerifySheet({required this.request, required this.pick});

  @override
  State<_PhotoVerifySheet> createState() => _PhotoVerifySheetState();
}

class _PhotoVerifySheetState extends State<_PhotoVerifySheet> {
  _PhotoStage _stage = _PhotoStage.choosing;

  /// 개인 트랙에서 사용자가 고른 카테고리. 팀은 고정값이라 안 쓴다.
  ChallengeCategory _category = ChallengeCategory.exercise;

  AiVerificationResult? _result;
  String _message = '';

  String? get _aiCategory => widget.request.fixedAiCategory ?? _category.aiValue;

  Future<void> _pickAndUpload(ImageSource source) async {
    final aiCategory = _aiCategory;
    if (aiCategory == null) {
      // 여기 오면 안 되는 값이다(기상 등). 그대로 보내면 서버가 500을 준다.
      setState(() {
        _stage = _PhotoStage.error;
        _message = '이 카테고리는 사진 인증을 지원하지 않아요';
      });
      return;
    }

    PickedImage? picked;
    try {
      picked = await widget.pick(source);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _PhotoStage.error;
        _message = '사진을 가져오지 못했어요. 권한을 확인해주세요';
      });
      return;
    }
    // 사용자가 고르기를 그만둔 것뿐이다. 실패로 처리하면 안 된다.
    if (picked == null || !mounted) return;

    setState(() => _stage = _PhotoStage.uploading);
    try {
      final result =
          await widget.request.upload(picked.path, picked.bytes, aiCategory);
      if (!mounted) return;
      setState(() {
        _result = result;
        _stage = result.passed ? _PhotoStage.passed : _PhotoStage.rejected;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _PhotoStage.error;
        _message = e.message;
      });
    }
  }

  /// 성공했을 때만 결과를 돌려준다 — 호출부가 이걸로 화면을 갱신할지 정한다.
  void _close() => Navigator.of(context).pop(_result?.passed == true ? _result : null);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: BC.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            ..._body(),
          ],
        ),
      ),
    );
  }

  List<Widget> _body() {
    switch (_stage) {
      case _PhotoStage.choosing:
        return _choosing();
      case _PhotoStage.uploading:
        return _uploading();
      case _PhotoStage.passed:
        return _passed();
      case _PhotoStage.rejected:
        return _rejected();
      case _PhotoStage.error:
        return _error();
    }
  }

  List<Widget> _choosing() {
    return [
      const Text('사진으로 인증하기',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(widget.request.subtitle,
          style: const TextStyle(fontSize: 13.5, color: BC.ink2, height: 1.5)),
      if (widget.request.fixedAiCategory == null) ...[
        const SizedBox(height: 18),
        const Text('무엇을 인증하나요?',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        // 개인 트랙에는 카테고리를 저장하는 곳이 없어서 매번 물어야 한다.
        const Text('사진을 어떤 기준으로 볼지 정해요.',
            style: TextStyle(fontSize: 12.5, color: BC.ink3)),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final category in ChallengeCategory.photoChoices) ...[
              if (category != ChallengeCategory.photoChoices.first)
                const SizedBox(width: 7),
              Expanded(
                child: SelectChip(
                  label: category.label,
                  selected: _category == category,
                  onTap: () => setState(() => _category = category),
                ),
              ),
            ],
          ],
        ),
      ],
      const SizedBox(height: 18),
      PrimaryButton(
        label: '사진 찍기',
        leadingIcon: Icons.photo_camera_rounded,
        onTap: () => _pickAndUpload(ImageSource.camera),
      ),
      const SizedBox(height: 8),
      _ghostButton('앨범에서 고르기', Icons.photo_library_rounded,
          () => _pickAndUpload(ImageSource.gallery)),
      const SizedBox(height: 10),
      const Text('JPG·PNG·WEBP · 10MB 이하',
          style: TextStyle(fontSize: 11.5, color: BC.ink3)),
      const SizedBox(height: 4),
      Center(child: _cancelButton('나중에')),
    ];
  }

  List<Widget> _uploading() {
    return [
      const SizedBox(height: 16),
      const Center(child: CircularProgressIndicator(color: BC.oMain)),
      const SizedBox(height: 18),
      const Center(
        child: Text('사진을 확인하는 중이에요…',
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
      ),
      const SizedBox(height: 6),
      const Center(
        child: Text('잠깐 걸릴 수 있어요.',
            style: TextStyle(fontSize: 12.5, color: BC.ink3)),
      ),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _passed() {
    final result = _result!;
    final confidence = result.confidencePercent;
    // 팀 인증은 스트릭을 주지 않아 currentStreak이 null로 온다. 예전엔 0으로
    // 읽혀 "누적 인증 0회"가 떴다 — 팀에는 없는 개념이니 줄 자체를 그리지 않는다.
    final streak = result.currentStreak;
    return [
      _resultHead(Icons.check_circle_rounded, BC.green, BC.greenSoft, '인증했어요'),
      const SizedBox(height: 14),
      if (streak != null) _resultRow('누적 인증', '$streak회'),
      if (result.rewardGranted) ...[
        const SizedBox(height: 8),
        _resultRow('스트릭 보상', '+100 코인', highlight: true),
      ],
      if (confidence != null) ...[
        const SizedBox(height: 8),
        _resultRow('확신도', '$confidence%'),
      ],
      if (result.detectedLabels.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('사진에서 읽은 것: ${result.detectedLabels.join(', ')}',
            style: const TextStyle(fontSize: 12, color: BC.ink3, height: 1.4)),
      ],
      const SizedBox(height: 18),
      PrimaryButton(label: '확인', onTap: _close),
    ];
  }

  List<Widget> _rejected() {
    final result = _result!;
    return [
      _resultHead(Icons.cancel_rounded, BC.oMain, BC.oSoft, '사진을 확인하지 못했어요'),
      const SizedBox(height: 12),
      Text(
        result.reason ?? '사진에서 인증할 내용을 찾지 못했어요.',
        style: const TextStyle(fontSize: 13.5, color: BC.ink2, height: 1.5),
      ),
      const SizedBox(height: 12),
      // 거절되면 서버가 체크인 레코드를 지운다 — PENDING이 하루를 점유해 재시도가
      // 막히는 걸 막으려는 것이다. 그래서 오늘이 끝난 게 아니다.
      const NoteBox(
        icon: Icons.refresh_rounded,
        child: Text('오늘 다시 시도할 수 있어요. 인증할 내용이 잘 보이게 찍어주세요.',
            style: TextStyle(fontSize: 12.5, color: BC.ink2, height: 1.5)),
      ),
      const SizedBox(height: 18),
      PrimaryButton(
        label: '다시 찍기',
        leadingIcon: Icons.photo_camera_rounded,
        onTap: () => setState(() => _stage = _PhotoStage.choosing),
      ),
      const SizedBox(height: 4),
      Center(child: _cancelButton('닫기')),
    ];
  }

  List<Widget> _error() {
    return [
      _resultHead(Icons.error_outline_rounded, BC.oMain, BC.oSoft, '올리지 못했어요'),
      const SizedBox(height: 12),
      Text(_message,
          style: const TextStyle(fontSize: 13.5, color: BC.ink2, height: 1.5)),
      const SizedBox(height: 12),
      // 502로 실패해도 체크인은 PENDING으로 남는다. 다시 올리면 된다.
      const NoteBox(
        icon: Icons.info_outline_rounded,
        child: Text('인증은 아직 남아 있어요. 다시 올리면 이어서 처리돼요.',
            style: TextStyle(fontSize: 12.5, color: BC.ink2, height: 1.5)),
      ),
      const SizedBox(height: 18),
      PrimaryButton(
        label: '다시 시도',
        onTap: () => setState(() => _stage = _PhotoStage.choosing),
      ),
      const SizedBox(height: 4),
      Center(child: _cancelButton('닫기')),
    ];
  }

  Widget _resultHead(IconData icon, Color fg, Color bg, String title) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(icon, size: 24, color: fg),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Text(title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }

  Widget _resultRow(String label, String value, {bool highlight = false}) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w600, color: BC.ink2)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: highlight ? BC.oMain : BC.ink)),
      ],
    );
  }

  Widget _ghostButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
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
                    fontSize: 14.5, fontWeight: FontWeight.w700, color: BC.ink)),
          ],
        ),
      ),
    );
  }

  Widget _cancelButton(String label) {
    return TextButton(
      onPressed: _close,
      child: Text(label,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: BC.ink3)),
    );
  }
}
