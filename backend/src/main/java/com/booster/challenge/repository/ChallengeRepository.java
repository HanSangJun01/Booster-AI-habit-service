package com.booster.challenge.repository;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.domain.ChallengeVisibility;
import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface ChallengeRepository extends JpaRepository<Challenge, Long> {

    Optional<Challenge> findByInviteCode(String inviteCode);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT c FROM Challenge c WHERE c.id = :id")
    Optional<Challenge> findByIdWithLock(@Param("id") Long id);

    @Query("SELECT c FROM Challenge c WHERE c.visibility = 'PUBLIC' AND c.status = :status " +
           "AND (:category IS NULL OR c.category = :category) " +
           "AND (:keyword IS NULL OR c.title LIKE %:keyword%)")
    Page<Challenge> searchPublic(@Param("status") ChallengeStatus status,
                                  @Param("category") String category,
                                  @Param("keyword") String keyword,
                                  Pageable pageable);

    List<Challenge> findByStatusAndEndedAtBefore(ChallengeStatus status, LocalDateTime threshold);

    List<Challenge> findByStatus(ChallengeStatus status);

    /** 이 사람이 만든 특정 상태의 챌린지. 탈퇴 시 모집 중인 방을 해산하는 데 쓴다. */
    List<Challenge> findByCreatedByAndStatus(Long createdBy, ChallengeStatus status);
}
