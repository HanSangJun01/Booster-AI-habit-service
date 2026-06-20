package com.booster.recovery.domain;

/** bs-20 Phase 3 복귀 미션 상태. */
public enum RecoveryStatus {
    PENDING,    // 복귀 대기
    COMPLETED,  // 복귀 성공
    FAILED      // 데드라인 초과 실패
}
