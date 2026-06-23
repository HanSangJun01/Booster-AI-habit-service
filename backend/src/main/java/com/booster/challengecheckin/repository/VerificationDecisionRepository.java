package com.booster.challengecheckin.repository;

import com.booster.challengecheckin.domain.VerificationDecision;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface VerificationDecisionRepository extends JpaRepository<VerificationDecision, Long> {

    Optional<VerificationDecision> findBySubmissionId(Long submissionId);
}
