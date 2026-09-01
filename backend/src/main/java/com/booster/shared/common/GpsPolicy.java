package com.booster.shared.common;

/**
 * GPS 인증 반경 정책.
 *
 * <p>상한이 없던 시절에는 반경 20,000,000m(지구 반 바퀴) 등록이 그대로 통과해서,
 * 서울에 장소를 등록하고 시드니에서 인증해도 성공했다. 위치 인증이 사실상
 * 무력화되는 구멍이라 상·하한을 둔다.
 *
 * <p>상한 1km는 "걸어서 갈 수 있는 같은 장소"의 현실적인 최대치다. 하한 10m는
 * 휴대폰 GPS 오차(보통 10~50m)보다 좁으면 제자리에서도 인증이 실패하기 때문이다.
 */
public final class GpsPolicy {

    /** 인증 반경 하한(m). 이보다 좁으면 GPS 오차 때문에 정상 사용자도 인증에 실패한다. */
    public static final int MIN_RADIUS_METERS = 10;

    /** 인증 반경 상한(m). */
    public static final int MAX_RADIUS_METERS = 1000;

    public static final String RADIUS_MESSAGE =
            "인증 반경은 " + MIN_RADIUS_METERS + "m 이상 " + MAX_RADIUS_METERS + "m 이하여야 합니다.";

    private GpsPolicy() {
    }
}
