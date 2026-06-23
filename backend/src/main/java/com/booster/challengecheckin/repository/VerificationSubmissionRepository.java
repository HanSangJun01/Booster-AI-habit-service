package com.booster.challengecheckin.repository;

import com.booster.challengecheckin.domain.VerificationSubmission;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface VerificationSubmissionRepository extends JpaRepository<VerificationSubmission, Long> {

    List<VerificationSubmission> findByCheckInId(Long checkInId);

    int countByCheckInId(Long checkInId);
}
