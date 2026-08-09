package com.booster.shared.contract;

import java.time.LocalDate;

/** A-axis PersonalCheckIn 호출 포트 (CheckInOrchestrator에서 사용). */
public interface PersonalCheckInPort {

    /** 개인 습관 인증 처리. 결과는 A-axis가 독립적으로 관리. */
    void recordPersonalCheckIn(Long userId, LocalDate date, double currentLat, double currentLng);
}
