package com.booster.personalcheckin.repository;

import com.booster.personalcheckin.domain.PersonalAiAttempt;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.Optional;

public interface PersonalAiAttemptRepository extends JpaRepository<PersonalAiAttempt, Long> {

    /** 그날의 판정 시도 수 — 하루 상한 검사용. */
    int countByUserIdAndAttemptDate(Long userId, LocalDate attemptDate);

    /** 가장 최근 시도 — 쿨다운 검사용. id 순서가 곧 시도 순서다. */
    Optional<PersonalAiAttempt> findTopByUserIdOrderByIdDesc(Long userId);

    /** 같은 사용자가 같은 이미지를 낸 적 있는가 — 사진 재사용 차단용. */
    boolean existsByUserIdAndImageSha256(Long userId, String imageSha256);
}
