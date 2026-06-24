package com.booster.personalcheckin.domain;

/** bs-25 Principle 3: 개인 체크인 상태 머신은 세 상태만 존재. */
public enum PersonalCheckInStatus {
    SUCCESS,          // 정상 인증(또는 복귀 미션으로 보정됨)
    RECOVERY_PENDING, // 미인증 → 복귀 미션 대기
    FAILED            // 복귀 미션 데드라인 초과 → 최종 실패
}
