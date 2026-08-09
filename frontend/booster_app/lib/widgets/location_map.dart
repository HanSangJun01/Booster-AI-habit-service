import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/location.dart';
import '../theme/booster_theme.dart';
import 'common.dart';

/// 인증 기준 위치를 지도로 보여주고 고르게 하는 위젯 모음.
///
/// 타일은 OSM 공개 서버를 쓴다. API 키도 결제 계정도 필요 없는 대신
/// [이용 정책](https://operations.osmfoundation.org/policies/tiles/)상
/// User-Agent 명시가 요구되고 대량 트래픽은 금지다. 팀 프로젝트/데모 규모는
/// 문제없지만, 실제 배포 때는 [_tileUrl]을 다른 제공자로 갈아끼워야 한다.
const String _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String _userAgent = 'com.example.booster_app';

/// OSM 타일이 존재하는 최대 줌. 이보다 크게 요청하면 타일이 404다.
const double _maxZoom = 19;

/// 반경 [radiusMeters]짜리 원이 높이 [boxHeight]인 지도 안에 적당히 들어오는
/// 줌을 구한다.
///
/// 반경을 20/30/50m 중에 고르게 해놓고 줌을 고정하면, 20m를 골랐을 때 원이
/// 점처럼 작아져서 "이게 얼마나 좁은지" 감이 안 온다. 반경이 바뀔 때마다
/// 화면에서 차지하는 비율이 일정하도록 줌을 다시 계산한다.
double zoomForRadius(double lat, int radiusMeters, double boxHeight) {
  // 원의 지름이 프레임 높이의 이만큼을 차지하게 한다. 1.0으로 두면 원이 딱
  // 맞게 차서 주변 지형이 안 보이고, 그러면 "여기가 맞나" 판단이 안 된다.
  const fill = 0.55;

  final targetPixels = boxHeight * fill;
  if (targetPixels <= 0) return _maxZoom;

  final metersPerPixel = (radiusMeters * 2) / targetPixels;

  // 웹 메르카토르에서 줌 0의 픽셀당 미터(적도 기준 156543.03392m)에
  // 위도 보정을 건다. 고위도로 갈수록 같은 줌에서 픽셀당 실제 거리가 짧아진다.
  final metersPerPixelAtZoom0 = 156543.03392 * math.cos(lat * math.pi / 180);

  final zoom = math.log(metersPerPixelAtZoom0 / metersPerPixel) / math.ln2;
  return zoom.clamp(3.0, _maxZoom);
}

/// 지도 위에 얹는 인증 반경 원.
CircleMarker _radiusCircle(LatLng center, int radiusMeters) => CircleMarker(
      point: center,
      radius: radiusMeters.toDouble(),
      useRadiusInMeter: true,
      color: BC.oMain.withValues(alpha: 0.16),
      borderColor: BC.oMain.withValues(alpha: 0.85),
      borderStrokeWidth: 2,
    );

/// 기준점을 가리키는 핀.
Widget _pin({double size = 34}) => Icon(
      Icons.location_on_rounded,
      size: size,
      color: BC.oMain,
      shadows: const [Shadow(color: Color(0x552B2B2B), blurRadius: 6, offset: Offset(0, 2))],
    );

TileLayer _tiles() => TileLayer(
      urlTemplate: _tileUrl,
      userAgentPackageName: _userAgent,
      maxNativeZoom: _maxZoom.toInt(),
    );

/// 등록된(또는 방금 잡은) 위치를 반경과 함께 보여주는 **읽기 전용** 지도.
///
/// 드래그·줌을 전부 끈다([InteractiveFlag.none]). 이 위젯이 들어가는 자리가
/// 스크롤되는 `ListView` 안이라, 지도가 제스처를 먹으면 세로 스크롤과 싸운다.
/// 위치를 옮기고 싶으면 [onTap]으로 [LocationPickerScreen]을 띄우는 방식이다.
class LocationPreviewMap extends StatefulWidget {
  final double lat;
  final double lng;
  final int radiusMeters;
  final double height;

  /// 탭했을 때. null이면 탭 반응이 없다.
  final VoidCallback? onTap;

  const LocationPreviewMap({
    super.key,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    this.height = 220,
    this.onTap,
  });

  @override
  State<LocationPreviewMap> createState() => _LocationPreviewMapState();
}

class _LocationPreviewMapState extends State<LocationPreviewMap> {
  final _controller = MapController();

  LatLng get _center => LatLng(widget.lat, widget.lng);

  double get _zoom => zoomForRadius(widget.lat, widget.radiusMeters, widget.height);

  @override
  void didUpdateWidget(LocationPreviewMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 좌표나 반경이 바뀌어도 MapOptions.initialCenter/initialZoom은 다시
    // 적용되지 않는다("initial"이라 최초 1회다). 컨트롤러로 직접 옮겨야
    // 반경 칩을 눌렀을 때 원이 커지고 줄어드는 게 보인다.
    if (oldWidget.lat != widget.lat ||
        oldWidget.lng != widget.lng ||
        oldWidget.radiusMeters != widget.radiusMeters ||
        oldWidget.height != widget.height) {
      _controller.move(_center, _zoom);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _controller,
                options: MapOptions(
                  initialCenter: _center,
                  initialZoom: _zoom,
                  maxZoom: _maxZoom,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  _tiles(),
                  CircleLayer(circles: [_radiusCircle(_center, widget.radiusMeters)]),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _center,
                        width: 34,
                        height: 34,
                        alignment: Alignment.topCenter,
                        child: _pin(),
                      ),
                    ],
                  ),
                ],
              ),
              if (widget.onTap != null)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: _mapChip(Icons.open_in_full_rounded, '지도에서 조정'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _mapChip(IconData icon, String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: BC.oMain),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: BC.ink)),
        ],
      ),
    );

/// 지도를 움직여 기준점을 고르는 전체 화면.
///
/// 핀을 끄는 대신 **핀은 화면 중앙에 고정하고 지도를 움직인다**. 손가락이
/// 핀을 가리지 않고, 작은 화면에서 정밀도도 더 낫다(주소 설정 화면들이
/// 대개 이 방식이다).
///
/// [Navigator.pop]으로 고른 [LatLng]을 돌려준다. 취소하면 null이다.
class LocationPickerScreen extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final int radiusMeters;

  const LocationPickerScreen({
    super.key,
    required this.initialLat,
    required this.initialLng,
    required this.radiusMeters,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _controller = MapController();
  late LatLng _center = LatLng(widget.initialLat, widget.initialLng);
  bool _locating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _goToCurrent() async {
    setState(() => _locating = true);
    try {
      final position = await LocationService.current();
      if (!mounted) return;
      final target = LatLng(position.latitude, position.longitude);
      _controller.move(target, _controller.camera.zoom);
      setState(() => _center = target);
    } on LocationException catch (e) {
      if (!mounted) return;
      showBoosterToast(context, e.message);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 전체 화면이라 원이 화면을 꽉 채우지 않게 프레임을 넉넉히 잡는다.
    final initialZoom =
        zoomForRadius(widget.initialLat, widget.radiusMeters, MediaQuery.of(context).size.height * 0.5);

    return Scaffold(
      backgroundColor: BC.bg,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: initialZoom,
              maxZoom: _maxZoom,
              interactionOptions: const InteractionOptions(
                // 회전은 뺀다. 두 손가락으로 확대하다 지도가 비스듬히 돌아가면
                // 되돌릴 방법을 찾기 어렵다.
                flags: InteractiveFlag.drag |
                    InteractiveFlag.flingAnimation |
                    InteractiveFlag.pinchMove |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom,
              ),
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) setState(() => _center = camera.center);
              },
            ),
            children: [
              _tiles(),
              CircleLayer(circles: [_radiusCircle(_center, widget.radiusMeters)]),
            ],
          ),

          // 화면 중앙 고정 핀. 지도 레이어 위에 얹되 제스처는 통과시킨다.
          IgnorePointer(
            child: Center(
              // 핀 끝(뾰족한 아래쪽)이 중앙에 오도록 아이콘 높이의 절반만큼 띄운다.
              child: Padding(
                padding: const EdgeInsets.only(bottom: 42),
                child: _pin(size: 42),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                BackAppBar(title: '인증 장소 선택'),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: _locating ? null : _goToCurrent,
                          child: _mapChip(
                            Icons.my_location_rounded,
                            _locating ? '위치 확인 중…' : '현재 위치로',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: BC.card,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              '지도를 움직여 인증 기준점을 맞춰주세요',
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w600, color: BC.ink2),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '위도 ${_center.latitude.toStringAsFixed(5)}  ·  경도 ${_center.longitude.toStringAsFixed(5)}',
                              style: const TextStyle(fontSize: 12.5, color: BC.ink3),
                            ),
                            const SizedBox(height: 12),
                            PrimaryButton(
                              label: '이 위치로 설정',
                              trailingIcon: Icons.check_rounded,
                              onTap: () => Navigator.of(context).pop(_center),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
