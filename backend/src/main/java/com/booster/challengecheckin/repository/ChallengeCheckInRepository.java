package com.booster.challengecheckin.repository;

import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.domain.CheckInStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface ChallengeCheckInRepository extends JpaRepository<ChallengeCheckIn, Long> {

    Optional<ChallengeCheckIn> findByParticipantIdAndCheckInDate(Long participantId, LocalDate date);

    List<ChallengeCheckIn> findByTeamIdAndCheckInDate(Long teamId, LocalDate date);

    long countByTeamIdAndStatusAndCheckInDateBetween(Long teamId, CheckInStatus status, LocalDate from, LocalDate to);

    List<ChallengeCheckIn> findByChallengeIdAndCheckInDate(Long challengeId, LocalDate date);

    List<ChallengeCheckIn> findByChallengeIdAndCheckInDateBetween(Long challengeId, LocalDate from, LocalDate to);

    long countByParticipantIdAndStatus(Long participantId, CheckInStatus status);
}
