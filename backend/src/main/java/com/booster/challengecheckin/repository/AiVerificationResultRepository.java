package com.booster.challengecheckin.repository;

import com.booster.challengecheckin.domain.AiVerificationResult;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface AiVerificationResultRepository extends JpaRepository<AiVerificationResult, Long> {

    Optional<AiVerificationResult> findBySubmissionId(Long submissionId);

    /** 같은 이미지(바이트 동일)로 저장된 과거 판정들. 사진 재사용 차단용. */
    List<AiVerificationResult> findAllByImageSha256(String imageSha256);
}
