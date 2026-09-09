package com.booster.challengecheckin.service;

import com.booster.challengecheckin.domain.AiVerificationResult;
import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.domain.VerificationSubmission;
import com.booster.challengecheckin.dto.AiServiceVerdict;
import com.booster.challengecheckin.repository.AiVerificationResultRepository;
import com.booster.challengecheckin.repository.ChallengeCheckInRepository;
import com.booster.challengecheckin.repository.VerificationDecisionRepository;
import com.booster.challengecheckin.repository.VerificationSubmissionRepository;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.common.BusinessException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockMultipartFile;

import java.math.BigDecimal;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

/**
 * (악용 방어) 사진 재사용 차단 — 같은 챌린지에서 이미 판정된 이미지(SHA-256 동일)는
 * AI 를 부르기 전에 409 DUPLICATE_IMAGE 로 끊는다. "헬스장 사진 한 장으로 30일" 과
 * 팀원 간 돌려쓰기를 함께 잡는 층이다.
 */
@ExtendWith(MockitoExtension.class)
class AiVerificationServiceTest {

    @Mock private VerificationSubmissionRepository submissionRepository;
    @Mock private AiVerificationResultRepository aiResultRepository;
    @Mock private VerificationDecisionRepository decisionRepository;
    @Mock private ChallengeCheckInRepository checkInRepository;
    @Mock private ChallengeParticipantRepository participantRepository;
    @Mock private AiVerificationClient aiVerificationClient;
    @Mock private ChallengeCheckInService challengeCheckInService;

    private AiVerificationService service;

    private final Long userId = 1L;
    private final Long submissionId = 7L;
    private final Long checkInId = 100L;
    private final Long participantId = 55L;
    private final Long challengeId = 10L;

    private final byte[] imageBytes = "fake-image-bytes".getBytes();

    @BeforeEach
    void setUp() {
        service = new AiVerificationService(
                submissionRepository, aiResultRepository, decisionRepository,
                checkInRepository, participantRepository, aiVerificationClient,
                challengeCheckInService, new ObjectMapper());
    }

    private void arrangeOwnedSubmission() {
        VerificationSubmission submission = VerificationSubmission.builder()
                .checkInId(checkInId)
                .submittedLat(37.5).submittedLng(127.0)
                .attemptNumber(1)
                .build();
        when(submissionRepository.findById(submissionId)).thenReturn(Optional.of(submission));

        ChallengeCheckIn checkIn = mock(ChallengeCheckIn.class);
        when(checkIn.getParticipantId()).thenReturn(participantId);
        when(checkIn.getChallengeId()).thenReturn(challengeId);
        when(checkInRepository.findById(checkInId)).thenReturn(Optional.of(checkIn));

        ChallengeParticipant participant = mock(ChallengeParticipant.class);
        when(participant.getUserId()).thenReturn(userId);
        when(participantRepository.findById(participantId)).thenReturn(Optional.of(participant));

        when(aiResultRepository.findBySubmissionId(submissionId)).thenReturn(Optional.empty());
    }

    private ChallengeCheckIn checkInOfChallenge(Long otherChallengeId) {
        ChallengeCheckIn prior = mock(ChallengeCheckIn.class);
        when(prior.getChallengeId()).thenReturn(otherChallengeId);
        return prior;
    }

    private static String sha256Hex(byte[] bytes) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
    }

    @Test
    void verifyAndSave_whenSameImageAlreadyUsedInSameChallenge_shouldRejectBeforeAiCall() {
        arrangeOwnedSubmission();

        // 같은 해시의 과거 판정이 같은 챌린지(checkIn 90 → challenge 10)에 존재
        AiVerificationResult prior = AiVerificationResult.builder()
                .submissionId(3L).modelName("m").isPassed(true)
                .confidenceScore(BigDecimal.ONE).detectedLabels("[]")
                .storageKey("k").imageSha256("x").build();
        when(aiResultRepository.findAllByImageSha256(anyString())).thenReturn(List.of(prior));
        VerificationSubmission priorSubmission = VerificationSubmission.builder()
                .checkInId(90L).submittedLat(0.0).submittedLng(0.0).attemptNumber(1).build();
        when(submissionRepository.findById(3L)).thenReturn(Optional.of(priorSubmission));
        ChallengeCheckIn priorCheckIn = checkInOfChallenge(challengeId);
        when(checkInRepository.findById(90L)).thenReturn(Optional.of(priorCheckIn));

        MockMultipartFile image = new MockMultipartFile(
                "image", "a.jpg", "image/jpeg", imageBytes);

        BusinessException ex = assertThrows(BusinessException.class,
                () -> service.verifyAndSave(userId, submissionId, "EXERCISE", image));

        assertEquals("DUPLICATE_IMAGE", ex.getCode());
        assertEquals(409, ex.getStatus().value());
        // 핵심: 과금되는 AI 호출 전에 끊었는가
        verify(aiVerificationClient, never()).verify(any(), any(), any(), any());
        verify(aiResultRepository, never()).save(any());
    }

    @Test
    void verifyAndSave_whenSameImageUsedInDifferentChallenge_shouldProceedAndStampHash()
            throws Exception {
        arrangeOwnedSubmission();

        // 같은 해시지만 **다른** 챌린지의 판정 — 오탐을 막기 위해 차단하지 않는다
        AiVerificationResult prior = AiVerificationResult.builder()
                .submissionId(3L).modelName("m").isPassed(true)
                .confidenceScore(BigDecimal.ONE).detectedLabels("[]")
                .storageKey("k").imageSha256("x").build();
        when(aiResultRepository.findAllByImageSha256(anyString())).thenReturn(List.of(prior));
        VerificationSubmission priorSubmission = VerificationSubmission.builder()
                .checkInId(90L).submittedLat(0.0).submittedLng(0.0).attemptNumber(1).build();
        when(submissionRepository.findById(3L)).thenReturn(Optional.of(priorSubmission));
        ChallengeCheckIn priorCheckIn = checkInOfChallenge(999L);
        when(checkInRepository.findById(90L)).thenReturn(Optional.of(priorCheckIn));

        when(aiVerificationClient.verify(any(), any(), any(), any())).thenReturn(
                new AiServiceVerdict(true, BigDecimal.valueOf(0.9), List.of("l"),
                        "model", "ok", "key", null));
        when(aiResultRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(decisionRepository.findBySubmissionId(any())).thenReturn(Optional.empty());

        MockMultipartFile image = new MockMultipartFile(
                "image", "a.jpg", "image/jpeg", imageBytes);

        service.verifyAndSave(userId, submissionId, "EXERCISE", image);

        // 이번 판정 결과에 이미지 지문이 박혀 이후의 재사용을 잡을 수 있어야 한다
        ArgumentCaptor<AiVerificationResult> captor =
                ArgumentCaptor.forClass(AiVerificationResult.class);
        verify(aiResultRepository).save(captor.capture());
        assertEquals(sha256Hex(imageBytes), captor.getValue().getImageSha256());
    }
}
