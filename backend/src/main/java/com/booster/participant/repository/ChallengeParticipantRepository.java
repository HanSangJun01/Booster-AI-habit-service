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

    /**
     * 주어진 챌린지들 중 이 사용자가 참여 중인 challengeId 집합.
     * 목록 응답의 {@code joined} 플래그를 페이지당 쿼리 1회로 채우기 위한 것(N+1 방지).
     * 종료된 참여(CANCELLED/REJECTED)는 "참여 중"이 아니므로 제외한다.
     */
    @Query("SELECT p.challenge.id FROM ChallengeParticipant p "
            + "WHERE p.userId = :userId AND p.challenge.id IN :challengeIds "
            + "AND p.status IN ('PENDING', 'CONFIRMED', 'LEFT')")
    List<Long> findJoinedChallengeIds(@Param("userId") Long userId,
                                      @Param("challengeIds") List<Long> challengeIds);

    /** 내가 참여 중인 참여 레코드(종료된 것 제외). */
    @Query("SELECT p FROM ChallengeParticipant p "
            + "WHERE p.userId = :userId AND p.status IN ('PENDING', 'CONFIRMED', 'LEFT') "
            + "ORDER BY p.id DESC")
    List<ChallengeParticipant> findActiveByUserId(@Param("userId") Long userId);

    /** 참가자 목록 조회(상태 필터 없음). */
    List<ChallengeParticipant> findByChallengeIdOrderByIdAsc(Long challengeId);

    @Query("SELECT p FROM ChallengeParticipant p WHERE p.teamId = :teamId AND p.status IN ('CONFIRMED', 'LEFT')")
    List<ChallengeParticipant> findByTeamId(@Param("teamId") Long teamId);

    @Query("SELECT p FROM ChallengeParticipant p WHERE p.challenge.id = :challengeId AND p.userId = :userId AND p.status = 'CONFIRMED'")
    Optional<ChallengeParticipant> findConfirmedByUserAndChallenge(@Param("challengeId") Long challengeId,
                                                                    @Param("userId") Long userId);
}
