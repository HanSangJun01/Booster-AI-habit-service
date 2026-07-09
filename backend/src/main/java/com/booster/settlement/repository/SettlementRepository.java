package com.booster.settlement.repository;

import com.booster.settlement.domain.Settlement;
import com.booster.settlement.domain.SettlementStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface SettlementRepository extends JpaRepository<Settlement, Long> {

    Optional<Settlement> findByChallengeId(Long challengeId);

    boolean existsByChallengeIdAndStatus(Long challengeId, SettlementStatus status);
}
