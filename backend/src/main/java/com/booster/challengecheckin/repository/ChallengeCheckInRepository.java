package com.booster.challengecheckin.repository;

import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.domain.CheckInStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface ChallengeCheckInRepository extends JpaRepository<ChallengeCheckIn, Long> {

    /** 참가자별 특정 상태 체크인 수를 단일 쿼리로 집계 (리더보드 N+1 제거). */
    @Query("""
        SELECT c.participantId AS participantId, COUNT(c) AS count
          FROM ChallengeCheckIn c
         WHERE c.challengeId = :challengeId AND c.status = :status
         GROUP BY c.participantId
        """)
    List<ParticipantCheckInCount> countByChallengeIdAndStatusGroupByParticipant(
            @Param("challengeId") Long challengeId, @Param("status") CheckInStatus status);

    /** 위 집계 쿼리의 인터페이스 프로젝션 (participantId → count). */
    interface ParticipantCheckInCount {
        Long getParticipantId();
        long getCount();
    }

    Optional<ChallengeCheckIn> findByParticipantIdAndCheckInDate(Long participantId, LocalDate date);

    List<ChallengeCheckIn> findByTeamIdAndCheckInDate(Long teamId, LocalDate date);

    long countByTeamIdAndStatusAndCheckInDateBetween(Long teamId, CheckInStatus status, LocalDate from, LocalDate to);

    List<ChallengeCheckIn> findByChallengeIdAndCheckInDate(Long challengeId, LocalDate date);

    List<ChallengeCheckIn> findByChallengeIdAndCheckInDateBetween(Long challengeId, LocalDate from, LocalDate to);

    long countByParticipantIdAndStatus(Long participantId, CheckInStatus status);
}
