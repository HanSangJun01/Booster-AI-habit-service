package com.booster.challenge.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.domain.ChallengeVisibility;
import com.booster.challenge.dto.ChallengeDetailResponse;
import com.booster.challenge.dto.ChallengeResponse;
import com.booster.challenge.dto.CreateChallengeRequest;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.participant.domain.ParticipantStatus;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.common.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ChallengeService {

    private final ChallengeRepository challengeRepository;
    private final ChallengeParticipantRepository participantRepository;
    private final InviteCodeGenerator inviteCodeGenerator;

    @Transactional
    public ChallengeResponse createChallenge(Long userId, CreateChallengeRequest request) {
        Challenge challenge = Challenge.builder()
                .category(request.getCategory())
                .title(request.getTitle())
                .description(request.getDescription())
                .verificationMethod(request.getVerificationMethod())
                .durationDays(request.getDurationDays())
                .depositCoins(request.getDepositCoins())
                .visibility(request.getVisibility())
                .approvalType(request.getApprovalType())
                .status(ChallengeStatus.RECRUITING)
                .maxParticipants(request.getMaxParticipants())
                .createdBy(userId)
                .build();

        if (request.getVisibility() == ChallengeVisibility.PRIVATE) {
            challenge.setInviteCode(inviteCodeGenerator.generate());
        }

        Challenge saved = challengeRepository.save(challenge);
        log.info("Challenge created: id={}, userId={}, visibility={}", saved.getId(), userId, saved.getVisibility());
        return ChallengeResponse.from(saved);
    }

    public Page<ChallengeResponse> searchPublicChallenges(String category, String keyword, Pageable pageable) {
        return challengeRepository.searchPublic(ChallengeStatus.RECRUITING, category, keyword, pageable)
                .map(ChallengeResponse::from);
    }

    public ChallengeDetailResponse getChallengeDetail(Long challengeId) {
        Challenge challenge = getOrThrow(challengeId);
        long confirmedCount = participantRepository.countByChallengeIdAndStatus(challengeId, ParticipantStatus.CONFIRMED);
        return ChallengeDetailResponse.from(challenge, confirmedCount);
    }

    public ChallengeResponse getChallengeByInviteCode(String code) {
        log.debug("Challenge lookup by invite code: {}", code);
        return challengeRepository.findByInviteCode(code)
                .map(ChallengeResponse::from)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge not found with invite code: " + code));
    }

    public Challenge getOrThrow(Long challengeId) {
        return challengeRepository.findById(challengeId)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge", challengeId));
    }
}
