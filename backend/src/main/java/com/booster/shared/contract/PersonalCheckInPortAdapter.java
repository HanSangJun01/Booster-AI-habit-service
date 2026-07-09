package com.booster.shared.contract;

import com.booster.personalcheckin.service.PersonalCheckInService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.time.LocalDate;

/**
 * B축 {@link PersonalCheckInPort} 포트 → A축 실제 개인 인증 서비스 어댑터.
 *
 * <p>{@code date}는 A축이 서버 클럭(오늘)로 판정하므로 참고용으로만 받는다(호출부 CheckInOrchestrator도
 * 항상 오늘을 전달). 개인 인증 실패(GPS 범위 밖·위치 미등록·중복 등 BusinessException)는 호출부에서
 * best-effort로 try/catch 처리되어 챌린지 체크인 결과에 영향을 주지 않는다.
 */
@Component
@RequiredArgsConstructor
public class PersonalCheckInPortAdapter implements PersonalCheckInPort {

    private final PersonalCheckInService personalCheckInService;

    @Override
    public void recordPersonalCheckIn(Long userId, LocalDate date, double currentLat, double currentLng) {
        personalCheckInService.checkIn(userId, currentLat, currentLng);
    }
}
