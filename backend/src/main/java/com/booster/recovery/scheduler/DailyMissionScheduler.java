package com.booster.recovery.scheduler;

import com.booster.recovery.service.RecoveryService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 매일 KST 00:01 실행. bs-20 §스케줄러 — 실행 순서 필수 준수:
 *   ① 만료된 복귀 미션 FAILED 처리 (Phase 3)
 *   ② 전일 미인증자 RECOVERY_PENDING 생성 (Phase 2)
 * ①이 먼저 실행되어야 새 PENDING 생성이 이미 만료된 건을 덮어쓰지 않는다.
 * 각 단계는 RecoveryService에서 @Transactional 로 분리 실행(멱등 보장).
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class DailyMissionScheduler {

    private final RecoveryService recoveryService;

    @Scheduled(cron = "0 1 0 * * *", zone = "Asia/Seoul")
    public void runDaily() {
        log.info("[DailyMissionScheduler] start");
        int expired = recoveryService.expireOverdueMissions();   // ①
        int created = recoveryService.generatePendingForYesterday(); // ②
        log.info("[DailyMissionScheduler] done. expired={}, created={}", expired, created);
    }
}
