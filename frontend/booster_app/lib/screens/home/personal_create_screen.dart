import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/api_client.dart';
import '../../core/location.dart';
import '../../models/personal_location.dart';
import '../../services/personal_service.dart';
import '../../theme/booster_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/location_map.dart';

/// 개인 인증 기준 위치 등록/변경 (`/api/users/me/location`).
///
/// 백엔드에 "개인 챌린지" 엔티티가 없어서(제목·기간·주 N회 필드가 존재하지
/// 않는다) 개인 트랙 설정은 사실상 이 하나다: **어디서 인증할 것인가**.
/// 등록한 좌표에서 [radiusMeters] 안에 있어야 `POST /api/personal/check-in`이
/// 성공한다.
///
/// 좌표는 현재 기기 위치로 먼저 잡고, 지도에서 미세 조정할 수 있게 한다
/// ("지금 있는 곳"이 인증 장소인 경우가 대부분이지만, 건물 안에서 GPS가
/// 튀거나 "집 앞"처럼 조금 떨어진 지점을 잡고 싶을 때가 있다).
class PersonalCreateScreen extends StatefulWidget {
  /// 이미 등록된 위치가 있으면 변경 모드로 연다.
  final PersonalLocation? current;

  const PersonalCreateScreen({super.key, this.current});

  @override
  State<PersonalCreateScreen> createState() => _PersonalCreateScreenState();
}

class _PersonalCreateScreenState extends State<PersonalCreateScreen> {
  final _placeCtrl = TextEditingController();

  /// 서버는 반경을 양수로만 검증하므로(`@Positive`) 상한은 앱이 정한다.
  ///
  /// 최대 50m다. 그 이상은 "그 장소에 있었다"는 판정이 무의미해진다 —
  /// 500m면 반경 안에 지하철 몇 정거장이 들어온다. 아래로는 20m가 하한인데,
  /// 휴대폰 GPS 오차가 통상 5~20m라 그보다 좁히면 제자리에 있어도 인증이
  /// 실패한다.
  static const _radiusOptions = [20, 30, 50];

  /// 기본값은 가장 넉넉한 50m. 처음 쓰는 사람이 오차로 실패하는 것보다 낫다.
  int _radiusIndex = 2;

  double? _latitude;
  double? _longitude;
  bool _locating = false;
  bool _saving = false;
  String? _locationError;

  bool get _isEdit => widget.current != null;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    if (current != null) {
      _placeCtrl.text = current.placeName ?? '';
      _latitude = current.lat;
      _longitude = current.lng;
      final idx = _radiusOptions.indexOf(current.radiusMeters);
      if (idx >= 0) _radiusIndex = idx;
    } else {
      _detectLocation();
    }
  }

  @override
  void dispose() {
    _placeCtrl.dispose();
    super.dispose();
  }

  Future<void> _detectLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final position = await LocationService.current();
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locating = false;
      });
    } on LocationException catch (e) {
      if (!mounted) return;
      setState(() {
        _locationError = e.message;
        _locating = false;
      });
    }
  }

  /// 지도에서 기준점을 직접 옮긴다. 반경은 이 화면이 들고 있으므로, 피커는
  /// 좌표만 돌려주고 반경은 현재 선택값을 그대로 보여주기만 한다.
  Future<void> _openPicker() async {
    final lat = _latitude;
    final lng = _longitude;
    if (lat == null || lng == null) return;

    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLat: lat,
          initialLng: lng,
          radiusMeters: _radiusOptions[_radiusIndex],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _latitude = picked.latitude;
      _longitude = picked.longitude;
    });
  }

  Future<void> _submit() async {
    final lat = _latitude;
    final lng = _longitude;
    if (lat == null || lng == null) {
      showBoosterToast(context, '먼저 현재 위치를 확인해주세요');
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await PersonalService.saveLocation(
        latitude: lat,
        longitude: lng,
        radiusMeters: _radiusOptions[_radiusIndex],
        placeName: _placeCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.bg,
      body: SafeArea(
        child: Column(
          children: [
            BackAppBar(
                title: _isEdit ? '인증 장소 변경' : '인증 장소 등록',
                trailing: const CoinPill()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                children: [
                  _card(
                    '1. 현재 위치',
                    sub: '지금 있는 곳을 인증 기준으로 잡아요. 지도를 눌러 조정할 수 있어요.',
                    child: _locationBox(),
                  ),
                  _card(
                    '2. 인증 반경',
                    sub: '이 반경 안에 있어야 인증이 성공해요.',
                    child: _chipRow(
                      [for (final r in _radiusOptions) '${r}m'],
                      _radiusIndex,
                      (i) => setState(() => _radiusIndex = i),
                    ),
                  ),
                  _card(
                    '3. 장소 이름',
                    sub: '선택 사항이에요. 안 적으면 좌표로 표시돼요.',
                    child: TextField(
                      controller: _placeCtrl,
                      maxLength: 200,
                      decoration: _inputDeco('예: 집 앞 헬스장'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
              child: PrimaryButton(
                label: _saving ? '저장하는 중...' : (_isEdit ? '변경 저장' : '등록하기'),
                trailingIcon: Icons.chevron_right_rounded,
                onTap: _submit,
                enabled: !_saving && _latitude != null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _locationBox() {
    final lat = _latitude;
    final lng = _longitude;
    final hasPoint = lat != null && lng != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasPoint)
          LocationPreviewMap(
            lat: lat,
            lng: lng,
            radiusMeters: _radiusOptions[_radiusIndex],
            onTap: _openPicker,
          )
        else
          _mapPlaceholder(),

        // 타일은 네트워크가 있어야 뜬다. GPS는 잡혔는데 데이터가 안 되는
        // 상황에서 지도만 두면 화면이 빈 회색이 되므로, 좌표는 항상 남긴다.
        if (hasPoint) ...[
          const SizedBox(height: 8),
          Text(
            '위도 ${lat.toStringAsFixed(5)}  ·  경도 ${lng.toStringAsFixed(5)}',
            style: const TextStyle(fontSize: 12.5, color: BC.ink3),
          ),
        ],
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _locating ? null : _detectLocation,
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BC.oSoft,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.my_location_rounded, size: 18, color: BC.oMain),
                SizedBox(width: 7),
                Text('현재 위치 다시 확인',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: BC.oMain)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 좌표가 아직 없을 때(위치 확인 중이거나 실패) 지도 자리를 채우는 박스.
  /// 지도는 좌표가 있어야 그릴 수 있어서, 이 상태에서는 지도를 띄우지 않는다.
  Widget _mapPlaceholder() {
    return Container(
      width: double.infinity,
      height: 220,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFEEF1F5), Color(0xFFE4E8EE)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD3D7DE)),
      ),
      child: Center(
        child: _locating
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(color: BC.oMain, strokeWidth: 2.5),
                  ),
                  SizedBox(height: 10),
                  Text('현재 위치를 확인하는 중…',
                      style: TextStyle(fontSize: 13, color: Color(0xFF8A8A92))),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_disabled_rounded, color: BC.ink3, size: 28),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Text(
                      _locationError ?? '위치를 확인하지 못했어요',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                          color: Color(0xFF6A6A72)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: BC.ink3),
        counterText: '',
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: BC.line, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: BC.oMain, width: 1.5),
        ),
      );

  Widget _card(String title, {String? sub, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(sub, style: const TextStyle(fontSize: 13, color: BC.ink2)),
            ],
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _chipRow(List<String> items, int sel, ValueChanged<int> onTap) {
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Expanded(
            child: SelectChip(
              label: items[i],
              selected: sel == i,
              onTap: () => onTap(i),
            ),
          ),
        ],
      ],
    );
  }
}
