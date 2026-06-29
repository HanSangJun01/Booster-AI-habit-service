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

    @Scheduled(fixedDelay = 60_000)
    public void markEndedChallenges() {
        log.debug("ChallengeEndScheduler running");
        List<Challenge> toEnd = challengeRepository.findByStatusAndEndedAtBefore(
                ChallengeStatus.ACTIVE, LocalDateTime.now());

        for (Challenge c : toEnd) {
            try {
                c.markEnded();
                challengeRepository.save(c);
                log.info("Challenge ended, triggering settlement: challengeId={}", c.getId());
                settlementService.settleChallenge(c.getId());
            } catch (Exception e) {
                log.error("Failed to end/settle challengeId={}", c.getId(), e);
            }
        }
    }

    // ENDED 상태 챌린지 중 정산이 FAILED이거나 settlement 자체가 없는 경우 재시도.
    // markEndedChallenges()와 별도 주기(5분)로 실행하여 FAILED 고착 방지.
    @Scheduled(fixedDelay = 300_000)
    public void retryFailedSettlements() {
        List<Challenge> endedChallenges = challengeRepository.findByStatus(ChallengeStatus.ENDED);
        for (Challenge c : endedChallenges) {
            boolean needsRetry = settlementRepository.findByChallengeId(c.getId())
                    .map(s -> s.getStatus() == SettlementStatus.FAILED)
                    .orElse(true);
            if (needsRetry) {
                log.info("Retrying settlement for ENDED challengeId={}", c.getId());
                try {
                    settlementService.settleChallenge(c.getId());
                } catch (Exception e) {
                    log.error("Retry settlement failed for challengeId={}", c.getId(), e);
                }
            }
        }
    }
}
