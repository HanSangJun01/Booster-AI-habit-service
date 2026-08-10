package com.booster.challengecheckin.service;

import com.booster.challengecheckin.domain.AiVerificationResult;
import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.domain.VerificationSubmission;
import com.booster.challengecheckin.dto.VerificationSubmissionDetail;
import com.booster.challengecheckin.repository.AiVerificationResultRepository;
import com.booster.challengecheckin.repository.ChallengeCheckInRepository;
import com.booster.challengecheckin.repository.GpsVerificationResultRepository;
import com.booster.challengecheckin.repository.VerificationDecisionRepository;
import com.booster.challengecheckin.repository.VerificationSubmissionRepository;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.common.ResourceNotFoundException;
import com.booster.shared.common.UnauthorizedException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * 인증 결과 상세 조회 (MVP_API_SPEC §9.2).
 *
 * <p>스펙에는 있었으나 컨트롤러가 없어 클라이언트가 인증 실패 사유를 확인할 수 없었다.
 * 특히 AI 인증은 "왜 거절됐는지"(reason·confidence)가 사용자에게 보여야 하는 정보다.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class VerificationQueryService {

    private final ChallengeCheckInRepository checkInRepository;
    private final ChallengeParticipantRepository participantRepository;
    private final VerificationSubmissionRepository submissionRepository;
    private final GpsVerificationResultRepository gpsResultRepository;
    private final AiVerificationResultRepository aiResultRepository;
    private final VerificationDecisionRepository decisionRepository;
    private final ObjectMapper objectMapper;

    /**
     * 체크인 1건의 인증 제출 이력.
     *
     * <p>★권한: 본인 체크인만. 다른 참여자의 인증 사진 키·GPS 좌표가 노출되면 안 된다
     * (BS-39 I14 체크인 열람과 동일 계열).
     */
    @Transactional(readOnly = true)
    public List<VerificationSubmissionDetail> getSubmissions(Long userId, Long checkInId) {
        ChallengeCheckIn checkIn = checkInRepository.findById(checkInId)
                .orElseThrow(() -> new ResourceNotFoundException("ChallengeCheckIn", checkInId));

        ChallengeParticipant participant = participantRepository.findById(checkIn.getParticipantId())
                .orElseThrow(() -> new ResourceNotFoundException(
                        "ChallengeParticipant", checkIn.getParticipantId()));
        if (!participant.getUserId().equals(userId)) {
            throw new UnauthorizedException("Not the owner of this check-in");
        }

        return submissionRepository.findByCheckInId(checkInId).stream()
                .map(this::toDetail)
                .toList();
    }

    private VerificationSubmissionDetail toDetail(VerificationSubmission s) {
        VerificationSubmissionDetail.GpsResult gps = gpsResultRepository.findBySubmissionId(s.getId())
                .map(g -> new VerificationSubmissionDetail.GpsResult(
                        g.getTargetLat(), g.getTargetLng(), g.getRadiusMeters(),
                        g.getDistanceMeters(), g.isWithinRadius()))
                .orElse(null);

        VerificationSubmissionDetail.AiResult ai = aiResultRepository.findBySubmissionId(s.getId())
                .map(a -> new VerificationSubmissionDetail.AiResult(
                        a.isPassed(), a.getConfidenceScore(), parseLabels(a),
                        a.getReason(), a.getModelName(), a.getStorageKey()))
                .orElse(null);

        VerificationSubmissionDetail.Decision decision = decisionRepository.findBySubmissionId(s.getId())
                .map(d -> new VerificationSubmissionDetail.Decision(
                        d.getDecisionStatus() != null ? d.getDecisionStatus().name() : null,
                        d.getFinalPassed(), d.getFailureReason()))
                .orElse(null);

        return new VerificationSubmissionDetail(
                s.getId(), s.getCheckInId(), s.getAttemptNumber(), s.getSubmittedAt(),
                s.getSubmittedLat(), s.getSubmittedLng(), gps, ai, decision);
    }

    /** detected_labels 는 TEXT 컬럼에 JSON 배열로 저장된다. 깨져 있어도 조회가 실패하면 안 된다. */
    private List<String> parseLabels(AiVerificationResult a) {
        if (a.getDetectedLabels() == null || a.getDetectedLabels().isBlank()) {
            return List.of();
        }
        try {
            return objectMapper.readValue(a.getDetectedLabels(), new TypeReference<List<String>>() {});
        } catch (Exception e) {
            log.warn("detected_labels 파싱 실패: aiResultId={}", a.getId());
            return List.of();
        }
    }
}
