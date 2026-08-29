package com.booster.personalcheckin.repository;

import com.booster.personalcheckin.domain.PersonalAiVerification;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface PersonalAiVerificationRepository extends JpaRepository<PersonalAiVerification, Long> {

    Optional<PersonalAiVerification> findByPersonalCheckInId(Long personalCheckInId);
}
