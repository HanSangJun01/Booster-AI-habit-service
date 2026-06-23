package com.booster.challengecheckin.repository;

import com.booster.challengecheckin.domain.GpsVerificationResult;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface GpsVerificationResultRepository extends JpaRepository<GpsVerificationResult, Long> {

    Optional<GpsVerificationResult> findBySubmissionId(Long submissionId);
}
