package com.booster.participant.repository;

import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.domain.ParticipantStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface ChallengeParticipantRepository extends JpaRepository<ChallengeParticipant, Long> {

    Optional<ChallengeParticipant> findByChallengeIdAndUserId(Long challengeId, Long userId);

    List<ChallengeParticipant> findByChallengeIdAndStatus(Long challengeId, ParticipantStatus status);

    long countByChallengeIdAndStatus(Long challengeId, ParticipantStatus status);

    List<ChallengeParticipant> findByUserId(Long userId);

    @Query("SELECT p FROM ChallengeParticipant p WHERE p.teamId = :teamId AND p.status IN ('CONFIRMED', 'LEFT')")
    List<ChallengeParticipant> findByTeamId(@Param("teamId") Long teamId);

    @Query("SELECT p FROM ChallengeParticipant p WHERE p.challenge.id = :challengeId AND p.userId = :userId AND p.status = 'CONFIRMED'")
    Optional<ChallengeParticipant> findConfirmedByUserAndChallenge(@Param("challengeId") Long challengeId,
                                                                    @Param("userId") Long userId);
}
