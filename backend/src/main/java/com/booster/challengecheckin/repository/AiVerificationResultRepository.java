package com.booster.challengecheckin.repository;

import com.booster.challengecheckin.domain.AiVerificationResult;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface AiVerificationResultRepository extends JpaRepository<AiVerificationResult, Long> {

    Optional<AiVerificationResult> findBySubmissionId(Long submissionId);
}
