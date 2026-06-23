package com.booster.settlement.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.repository.ChallengeRepository;
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
}
