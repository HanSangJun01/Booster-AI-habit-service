package com.booster.challengecheckin.service;

import com.booster.challengecheckin.domain.AiVerificationResult;
import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.domain.VerificationDecision;
import com.booster.challengecheckin.domain.VerificationSubmission;
import com.booster.challengecheckin.dto.AiServiceVerdict;
import com.booster.challengecheckin.dto.AiVerificationResponse;
import com.booster.challengecheckin.repository.AiVerificationResultRepository;
import com.booster.challengecheckin.repository.ChallengeCheckInRepository;
import com.booster.challengecheckin.repository.VerificationDecisionRepository;
import com.booster.challengecheckin.repository.VerificationSubmissionRepository;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.common.ResourceNotFoundException;
import com.booster.shared.common.UnauthorizedException;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional
public class AiVerificationService {

    private static final List<String> ALLOWED_TYPES = List.of(
            MediaType.IMAGE_JPEG_VALUE,
            MediaType.IMAGE_PNG_VALUE,
            "image/webp"
    );
    private static final long MAX_BYTES = 10L * 1024 * 1024;

    private final VerificationSubmissionRepository submissionRepository;
    private final AiVerificationResultRepository aiResultRepository;
    private final VerificationDecisionRepository decisionRepository;
    private final ChallengeCheckInRepository checkInRepository;
    private final ChallengeParticipantRepository participantRepository;
    private final AiVerificationClient aiVerificationClient;
    private final ChallengeCheckInService challengeCheckInService;
    private final ObjectMapper objectMapper;

    public AiVerificationResponse verifyAndSave(
            Long userId,
            Long submissionId,
            String category,
            MultipartFile image
    ) {
        VerificationSubmission submission = submissionRepository.findById(submissionId)
                .orElseThrow(() -> new ResourceNotFoundException("VerificationSubmission", submissionId));

        // 소유권 검증 — 이 submission이 정말 이 유저의 것인지
        ChallengeCheckIn checkIn = checkInRepository.findById(submission.getCheckInId())
                .orElseThrow(() -> new ResourceNotFoundException("ChallengeCheckIn", submission.getCheckInId()));
        ChallengeParticipant participant = participantRepository.findById(checkIn.getParticipantId())
                .orElseThrow(() -> new ResourceNotFoundException("ChallengeParticipant", checkIn.getParticipantId()));
        if (!participant.getUserId().equals(userId)) {
            throw new UnauthorizedException(
                    "Not the owner of this verification submission");
        }

        aiResultRepository.findBySubmissionId(submissionId).ifPresent(existing -> {
            throw new IllegalStateException(
                    "AI verification already exists for submission " + submissionId);
        });

        validateImage(image);

        byte[] bytes;
        try {
            bytes = image.getBytes();
        } catch (IOException e) {
            throw new AiVerificationException(HttpStatus.BAD_REQUEST, "이미지 읽기 실패", e);
        }

        MediaType mediaType = MediaType.parseMediaType(image.getContentType());
        String filename = image.getOriginalFilename() != null
                ? image.getOriginalFilename()
                : "upload";

        AiServiceVerdict verdict = aiVerificationClient.verify(category, bytes, filename, mediaType);

        AiVerificationResult saved = aiResultRepository.save(AiVerificationResult.builder()
                .submissionId(submission.getId())
                .modelName(verdict.modelName())
                .isPassed(verdict.passed())
                .confidenceScore(verdict.confidenceScore())
                .detectedLabels(writeJson(verdict.detectedLabels()))
                .reason(verdict.reason())
                .storageKey(verdict.storageKey())
                .rawResponse(writeJson(verdict.rawResponse()))
                .build());

        log.info("AI verification saved: submissionId={}, passed={}, confidence={}",
                submission.getId(), verdict.passed(), verdict.confidenceScore());

        // AI 결과를 반영해 verification_decisions PENDING → CONFIRMED로 확정
        challengeCheckInService.finalizeDecisionAfterAi(submission.getId(), verdict.passed());

        Boolean finalPassed = decisionRepository.findBySubmissionId(submission.getId())
                .map(VerificationDecision::getFinalPassed)
                .orElse(null);

        return toResponse(saved, verdict.detectedLabels(), finalPassed);
    }

    private void validateImage(MultipartFile image) {
        if (image == null || image.isEmpty()) {
            throw new AiVerificationException(HttpStatus.BAD_REQUEST, "이미지 파일이 비어있음");
        }
        if (image.getSize() > MAX_BYTES) {
            throw new AiVerificationException(HttpStatus.PAYLOAD_TOO_LARGE, "이미지 크기 10MB 초과");
        }
        String contentType = image.getContentType();
        if (contentType == null || !ALLOWED_TYPES.contains(contentType)) {
            throw new AiVerificationException(HttpStatus.UNSUPPORTED_MEDIA_TYPE,
                    "지원하지 않는 이미지 형식: " + contentType);
        }
    }

    private String writeJson(Object value) {
        if (value == null) return null;
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            log.warn("JSON 직렬화 실패, null로 저장", e);
            return null;
        }
    }

    private AiVerificationResponse toResponse(
            AiVerificationResult saved,
            List<String> labels,
            Boolean finalPassed) {
        return new AiVerificationResponse(
                saved.getId(),
                saved.getSubmissionId(),
                saved.isPassed(),
                saved.getConfidenceScore(),
                labels,
                saved.getReason(),
                saved.getModelName(),
                saved.getStorageKey(),
                saved.getCreatedAt(),
                finalPassed
        );
    }
}
