package com.booster.personalcheckin.service;

import com.booster.challengecheckin.dto.AiServiceVerdict;
import com.booster.challengecheckin.service.AiVerificationClient;
import com.booster.challengecheckin.service.AiVerificationException;
import com.booster.personalcheckin.domain.PersonalAiVerification;
import com.booster.personalcheckin.domain.PersonalCheckIn;
import com.booster.personalcheckin.dto.PersonalAiVerificationResponse;
import com.booster.personalcheckin.repository.PersonalAiVerificationRepository;
import com.booster.personalcheckin.repository.PersonalCheckInRepository;
import com.booster.shared.common.BusinessException;
import com.booster.user.domain.User;
import com.booster.user.repository.UserRepository;
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
import java.time.Clock;
import java.time.OffsetDateTime;
import java.util.List;

/**
 * 개인 습관의 AI 사진 인증.
 *
 * <p>인증 방식이 AI 를 포함하면 체크인이 {@code PENDING} 으로 만들어지고, 여기서 사진을 받아
 * 확정한다. 통과하면 출석·스트릭·마일스톤 보상이 그때 적용된다(GPS 인증과 동일한 경로를 공유).
 *
 * <p>ai-service 호출은 팀 챌린지와 같은 {@link AiVerificationClient} 를 쓴다 — 그 클라이언트는
 * 축에 의존하지 않고 "카테고리 + 이미지 → 판정" 만 담당하므로 그대로 재사용할 수 있다.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PersonalAiVerificationService {

    private static final List<String> ALLOWED_TYPES = List.of(
            MediaType.IMAGE_JPEG_VALUE, MediaType.IMAGE_PNG_VALUE, "image/webp");
    private static final long MAX_BYTES = 10L * 1024 * 1024;

    private final PersonalCheckInRepository checkInRepository;
    private final PersonalAiVerificationRepository aiRepository;
    private final UserRepository userRepository;
    private final AiVerificationClient aiVerificationClient;
    private final PersonalCheckInService personalCheckInService;
    private final ObjectMapper objectMapper;
    private final Clock clock;

    @Transactional
    public PersonalAiVerificationResponse verifyAndSave(Long userId, Long checkInId,
                                                       String category, MultipartFile image) {
        // 사용자 행을 먼저 잠근다 — 확정 시 출석·스트릭·코인을 만지므로 GPS 인증과 같은 락 순서를 지킨다.
        User user = userRepository.findByIdForUpdate(userId)
                .orElseThrow(() -> BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다."));
        if (!user.isActive()) {
            throw BusinessException.forbidden("INACTIVE_USER", "비활성(탈퇴) 계정입니다.");
        }

        PersonalCheckIn checkIn = checkInRepository.findById(checkInId)
                .orElseThrow(() -> BusinessException.notFound(
                        "CHECK_IN_NOT_FOUND", "체크인을 찾을 수 없습니다."));

        // 소유권 — 남의 체크인에 사진을 올릴 수 없다.
        if (!checkIn.getUserId().equals(userId)) {
            throw BusinessException.forbidden("NOT_CHECK_IN_OWNER", "본인의 체크인이 아닙니다.");
        }
        // 이미 확정된 체크인에 다시 올릴 수 없다 — 통과할 때까지 재시도하는 것을 막는다.
        if (!checkIn.isPending()) {
            throw BusinessException.conflict("CHECK_IN_ALREADY_CONFIRMED",
                    "이미 인증이 완료된 체크인입니다.");
        }

        validateImage(image);

        byte[] bytes;
        try {
            bytes = image.getBytes();
        } catch (IOException e) {
            throw new AiVerificationException(HttpStatus.BAD_REQUEST, "이미지 읽기 실패", e);
        }
        String filename = image.getOriginalFilename() != null ? image.getOriginalFilename() : "upload";

        AiServiceVerdict verdict = aiVerificationClient.verify(
                category, bytes, filename, MediaType.parseMediaType(image.getContentType()));

        aiRepository.save(PersonalAiVerification.of(
                checkIn.getId(), verdict.modelName(), verdict.passed(), verdict.confidenceScore(),
                writeJson(verdict.detectedLabels()), verdict.reason(), verdict.storageKey()));

        int streak;
        boolean rewardGranted = false;
        if (verdict.passed()) {
            checkIn.confirm(OffsetDateTime.now(clock));
            PersonalCheckInService.SuccessOutcome outcome =
                    personalCheckInService.applySuccess(userId, user, checkIn.getDate());
            streak = outcome.streak().getCurrentStreak();
            rewardGranted = outcome.rewardGranted();
            log.info("[PersonalAI] confirmed: userId={}, date={}", userId, checkIn.getDate());
        } else {
            // 거절되면 체크인 레코드를 지운다 — 그날을 "안 한 날"로 되돌려 다시 시도할 수 있게 한다.
            // (남겨두면 PENDING 이 하루를 점유해 재시도가 막힌다)
            checkInRepository.delete(checkIn);
            streak = 0;
            log.info("[PersonalAI] rejected: userId={}, date={}, reason={}",
                    userId, checkIn.getDate(), verdict.reason());
        }

        return new PersonalAiVerificationResponse(
                checkIn.getDate(), verdict.passed(), verdict.confidenceScore(),
                verdict.detectedLabels(), verdict.reason(), verdict.modelName(),
                verdict.passed() ? streak : null, user.getCoinBalance(), rewardGranted);
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
        if (value == null) {
            return "[]";
        }
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            log.warn("detected_labels 직렬화 실패", e);
            return "[]";
        }
    }
}
