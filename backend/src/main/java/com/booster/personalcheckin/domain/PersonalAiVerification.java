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
import org.hibernate.annotations.CreationTimestamp;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

/**
 * 개인 습관의 AI 사진 판정 결과. 체크인과 1:1.
 *
 * <p>팀 챌린지는 재시도 이력을 남기려고 {@code verification_submissions} 를 거치지만, 개인은
 * (user_id, date) 로 하루 1건이 유니크하고 재시도 이력을 남길 이유가 없어 체크인에 직접 붙인다.
 *
 * <p>{@code UNIQUE(personal_check_in_id)} 가 한 체크인에 판정이 두 번 저장되는 것을 막는다.
 * 사진을 올려 통과할 때까지 계속 재시도하는 것을 차단하는 게 아니라(그건 서비스에서 상태로 막는다),
 * 동시 요청으로 판정이 중복 기록되는 것을 막기 위한 것이다.
 */
@Entity
@Table(name = "personal_ai_verifications")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder(access = AccessLevel.PRIVATE)
public class PersonalAiVerification {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "personal_check_in_id", nullable = false)
    private Long personalCheckInId;

    @Column(name = "model_name", nullable = false, length = 100)
    private String modelName;

    @Column(name = "is_passed", nullable = false)
    private boolean passed;

    @Column(name = "confidence_score", nullable = false, precision = 5, scale = 4)
    private BigDecimal confidenceScore;

    /** ai-service 가 감지한 시각 요소들. JSON 배열 문자열로 저장한다. */
    @Column(name = "detected_labels", nullable = false)
    private String detectedLabels;

    /** 판정 근거(한국어 1~2문장). 사용자에게 "왜 거절됐는지" 보여주는 값이다. */
    @Column(length = 500)
    private String reason;

    /** 원본 이미지는 ai-service 의 storage 가 소유하고 여기서는 키로만 참조한다. */
    @Column(name = "storage_key", nullable = false, length = 500)
    private String storageKey;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    public static PersonalAiVerification of(Long personalCheckInId, String modelName, boolean passed,
                                            BigDecimal confidenceScore, String detectedLabels,
                                            String reason, String storageKey) {
        return PersonalAiVerification.builder()
                .personalCheckInId(personalCheckInId)
                .modelName(modelName)
                .passed(passed)
                .confidenceScore(confidenceScore)
                .detectedLabels(detectedLabels)
                .reason(reason)
                .storageKey(storageKey)
                .build();
    }
}
