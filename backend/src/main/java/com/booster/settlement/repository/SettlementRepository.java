package com.booster.settlement.repository;

import com.booster.settlement.domain.Settlement;
import com.booster.settlement.domain.SettlementStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface SettlementRepository extends JpaRepository<Settlement, Long> {

    Optional<Settlement> findByChallengeId(Long challengeId);

    boolean existsByChallengeIdAndStatus(Long challengeId, SettlementStatus status);

    /**
     * [P1 이중지급 차단] FAILED → PENDING 원자적 compare-and-set.
     * 기존 FAILED 정산의 재시도 경로는 INSERT가 없어 challenge_id unique 제약이 걸리지 않는다 →
     * 두 호출자가 동시에 멱등 게이트를 통과해 코인을 이중 지급할 수 있다. 이 조건부 UPDATE로
     * 오직 한 호출자만 status를 FAILED에서 PENDING으로 전이(1행 반환)시켜 재시도 소유권을 직렬화한다.
     *
     * @return 갱신된 행 수(이 호출자가 CAS에서 이겼으면 1, 이미 다른 호출자가 선점했으면 0)
     */
    @Modifying
    @Query("update Settlement s set s.status = 'PENDING' "
            + "where s.challengeId = :challengeId and s.status = 'FAILED'")
    int claimFailedForRetry(@Param("challengeId") Long challengeId);
}
