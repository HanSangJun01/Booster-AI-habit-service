package com.booster.recovery.repository;

import com.booster.recovery.domain.RecoveryMission;
import com.booster.recovery.domain.RecoveryStatus;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

public interface RecoveryMissionRepository extends JpaRepository<RecoveryMission, Long> {

    Optional<RecoveryMission> findFirstByUserIdAndStatusOrderByDeadlineAtAsc(
            Long userId, RecoveryStatus status);

    /** 스케줄러 ① 단계: 데드라인이 지난 PENDING 미션. */
    List<RecoveryMission> findByStatusAndDeadlineAtLessThanEqual(
            RecoveryStatus status, OffsetDateTime threshold);

    /**
     * (BS-30 C2) 복귀 수행용 — 사용자의 PENDING 미션을 비관적 쓰기락으로 조회.
     * 동시 2건이 같은 미션을 잡으면 하나만 락을 획득하고, 다른 하나는 대기 후 재평가에서
     * status=PENDING 이 더 이상 참이 아니어서 빈 결과를 받는다(READ_COMMITTED) → 정확히 1회 처리.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select m from RecoveryMission m "
            + "where m.userId = :userId and m.status = com.booster.recovery.domain.RecoveryStatus.PENDING "
            + "order by m.deadlineAt asc")
    List<RecoveryMission> findPendingByUserForUpdate(@Param("userId") Long userId);

    /**
     * (BS-30 C6/C7) 스케줄러 만료용 — 데드라인 초과 PENDING 미션을 비관적 쓰기락으로 조회.
     * 스케줄러 중복 실행/수행 경계 충돌 시 이중 처리를 막는다.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select m from RecoveryMission m "
            + "where m.status = com.booster.recovery.domain.RecoveryStatus.PENDING "
            + "and m.deadlineAt <= :threshold "
            + "order by m.id asc")
    List<RecoveryMission> findOverduePendingForUpdate(@Param("threshold") OffsetDateTime threshold);
}
