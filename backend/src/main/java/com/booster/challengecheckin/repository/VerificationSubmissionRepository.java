package com.booster.challengecheckin.repository;

import com.booster.challengecheckin.domain.VerificationSubmission;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface VerificationSubmissionRepository extends JpaRepository<VerificationSubmission, Long> {

    List<VerificationSubmission> findByCheckInId(Long checkInId);

    int countByCheckInId(Long checkInId);

    /** 가장 최근 판정 시도. 시도 간 쿨다운 검사용 — id 순서가 곧 제출 순서다. */
    Optional<VerificationSubmission> findTopByCheckInIdOrderByIdDesc(Long checkInId);
}
