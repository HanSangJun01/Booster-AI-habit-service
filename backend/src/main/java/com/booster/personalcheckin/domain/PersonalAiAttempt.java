package com.booster.personalcheckin.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDate;
import java.time.OffsetDateTime;

/**
 * (BS-41 악용 방어) 개인 트랙 AI 판정 시도 대장.
 *
 * <p>개인 트랙은 AI 가 거절하면 체크인을 삭제해 재시도를 열어주므로,
 * {@code personal_ai_verifications} 가 CASCADE 로 함께 지워져 시도 이력이 남지 않는다.
 * 하루 시도 상한·쿨다운·사진 재사용 차단은 삭제에서 살아남는 기록이 있어야 성립해서,
 * 체크인과 FK 로 묶지 않는 이 대장에 판정이 내려진 시도마다 한 행을 남긴다.
 *
 * <p>{@code created_at} 은 DB 시각이 아니라 서비스의 {@code Clock} 으로 찍는다 —
 * 쿨다운 판정과 같은 시계를 써야 하고, 테스트가 {@code MutableClock} 으로 시간을
 * 움직일 수 있어야 하기 때문이다.
 */
@Entity
@Table(name = "personal_ai_attempts")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder(access = AccessLevel.PRIVATE)
public class PersonalAiAttempt {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    /** 습관 날짜(KST) — 하루 시도 상한의 카운트 키. 체크인의 date 와 같은 값이다. */
    @Column(name = "attempt_date", nullable = false)
    private LocalDate attemptDate;

    /** 원본 이미지의 SHA-256(hex). 같은 사용자의 사진 재사용 차단 지문. */
    @Column(name = "image_sha256", nullable = false, length = 64)
    private String imageSha256;

    @Column(name = "is_passed", nullable = false)
    private boolean passed;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    public static PersonalAiAttempt of(Long userId, LocalDate attemptDate, String imageSha256,
                                       boolean passed, OffsetDateTime createdAt) {
        return PersonalAiAttempt.builder()
                .userId(userId)
                .attemptDate(attemptDate)
                .imageSha256(imageSha256)
                .passed(passed)
                .createdAt(createdAt)
                .build();
    }
}
