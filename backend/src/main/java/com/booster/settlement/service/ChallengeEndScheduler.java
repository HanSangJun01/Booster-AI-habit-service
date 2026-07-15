package com.booster.settlement.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.settlement.domain.SettlementStatus;
import com.booster.settlement.repository.SettlementRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.util.List;

@Slf4j
@Component
@RequiredArgsConstructor
public class ChallengeEndScheduler {

    private final ChallengeRepository challengeRepository;
    private final SettlementService settlementService;
    private final SettlementRepository settlementRepository;
    private final SettlementFailureRecorder failureRecorder;

    @Scheduled(fixedDelay = 60_000)
    public void markEndedChallenges() {
        try {
            log.debug("ChallengeEndScheduler running");
            List<Challenge> toEnd = challengeRepository.findByStatusAndEndedAtBefore(
                    ChallengeStatus.ACTIVE, LocalDateTime.now());

            for (Challenge c : toEnd) {
                try {
                    c.markEnded();
                    challengeRepository.save(c);
                    log.info("Challenge ended, triggering settlement: challengeId={}", c.getId());
                } catch (Throwable e) {
                    log.error("Failed to end challengeId={}", c.getId(), e);
                    continue;
                }
                settleAndRecordFailure(c.getId());
            }
        } catch (Throwable e) {
            log.error("markEndedChallenges crashed", e);
        }
    }

    // ENDED 상태 챌린지 중 정산이 FAILED이거나 settlement 자체가 없는 경우 재시도.
    // markEndedChallenges()와 별도 주기(5분)로 실행하여 FAILED 고착 방지.
    @Scheduled(fixedDelay = 300_000)
    public void retryFailedSettlements() {
        try {
            List<Challenge> endedChallenges = challengeRepository.findByStatus(ChallengeStatus.ENDED);
            for (Challenge c : endedChallenges) {
                boolean needsRetry = settlementRepository.findByChallengeId(c.getId())
                        .map(s -> s.getStatus() == SettlementStatus.FAILED)
                        .orElse(true);
                if (needsRetry) {
                    log.info("Retrying settlement for ENDED challengeId={}", c.getId());
                    settleAndRecordFailure(c.getId());
                }
            }
        } catch (Throwable e) {
            log.error("retryFailedSettlements crashed", e);
        }
    }

    // [교착 수정] FAILED 기록은 settleChallenge의 @Transactional이 롤백을 마친 "이후"
    // 별도 트랜잭션(REQUIRES_NEW)으로 수행해야 한다. settleChallenge 내부 catch에서
    // 기록하면, 그 트랜잭션이 INSERT한 미커밋 PENDING 행(unique challenge_id)을
    // 같은 스레드의 새 트랜잭션이 기다리는 self-deadlock으로 스케줄러 스레드가 죽는다.
    private void settleAndRecordFailure(Long challengeId) {
        try {
            settlementService.settleChallenge(challengeId);
        } catch (Throwable e) {
            log.error("Settlement failed, recording FAILED: challengeId={}", challengeId, e);
            try {
                failureRecorder.recordFailure(challengeId);
            } catch (Throwable re) {
                log.error("Failed to record settlement FAILED for challengeId={}", challengeId, re);
            }
        }
    }
}
