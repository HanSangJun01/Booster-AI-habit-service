package com.booster.settlement.service;

import com.booster.settlement.domain.Settlement;
import com.booster.settlement.domain.SettlementStatus;
import com.booster.settlement.repository.SettlementRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Component
@RequiredArgsConstructor
public class SettlementFailureRecorder {

    private final SettlementRepository settlementRepository;

    // REQUIRES_NEW 트랜잭션으로 FAILED 상태를 별도 커밋.
    // 외부 트랜잭션이 롤백되더라도 이 트랜잭션은 독립적으로 커밋된다.
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordFailure(Long challengeId) {
        Settlement settlement = settlementRepository.findByChallengeId(challengeId)
                .orElseGet(() -> Settlement.builder()
                        .challengeId(challengeId)
                        .status(SettlementStatus.PENDING)
                        .build());
        settlement.fail();
        settlementRepository.save(settlement);
        log.info("Settlement FAILED recorded for challengeId={}", challengeId);
    }
}
