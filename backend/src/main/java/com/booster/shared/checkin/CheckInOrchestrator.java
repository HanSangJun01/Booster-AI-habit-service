package com.booster.shared.checkin;

import com.booster.challengecheckin.dto.CheckInResponse;
import com.booster.challengecheckin.service.ChallengeCheckInService;
import com.booster.challengecheckin.service.TeamDetailCacheEvictor;
import com.booster.shared.contract.PersonalCheckInPort;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.time.ZoneId;

@Slf4j
@Component
@RequiredArgsConstructor
public class CheckInOrchestrator {

    private final ChallengeCheckInService challengeCheckInService;
    private final PersonalCheckInPort personalCheckInPort;
    private final TeamDetailCacheEvictor teamDetailCacheEvictor;

    public CheckInResponse performCheckIn(Long userId, Long challengeId, double currentLat, double currentLng) {
        // 1. B-axis 챌린지 체크인 (핵심 결과)
        CheckInResponse result = challengeCheckInService.recordCheckIn(userId, challengeId, currentLat, currentLng);

        // 1-1. 체크인이 반영되도록 해당 챌린지의 team-detail 캐시를 무효화 (트랜잭션 커밋 후)
        teamDetailCacheEvictor.evictChallenge(challengeId);

        // 2. A-axis 개인 체크인 (독립 호출 — 실패해도 B-axis 결과에 영향 없음)
        try {
            LocalDate today = LocalDate.now(ZoneId.of("Asia/Seoul"));
            personalCheckInPort.recordPersonalCheckIn(userId, today, currentLat, currentLng);
        } catch (Exception e) {
            log.warn("[CheckInOrchestrator] PersonalCheckIn failed for userId={}, challengeId={}: {}",
                    userId, challengeId, e.getMessage());
        }

        return result;
    }
}
