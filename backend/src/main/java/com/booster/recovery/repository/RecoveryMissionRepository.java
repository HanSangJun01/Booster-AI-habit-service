package com.booster.recovery.repository;

import com.booster.recovery.domain.RecoveryMission;
import com.booster.recovery.domain.RecoveryStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

public interface RecoveryMissionRepository extends JpaRepository<RecoveryMission, Long> {

    Optional<RecoveryMission> findFirstByUserIdAndStatusOrderByDeadlineAtAsc(
            Long userId, RecoveryStatus status);

    /** 스케줄러 ① 단계: 데드라인이 지난 PENDING 미션. */
    List<RecoveryMission> findByStatusAndDeadlineAtLessThanEqual(
            RecoveryStatus status, OffsetDateTime threshold);
}
