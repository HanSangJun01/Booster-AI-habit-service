package com.booster.participant.service;

import com.booster.challenge.domain.ApprovalType;
import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.domain.ParticipantStatus;
import com.booster.participant.dto.ParticipationRequest;
import com.booster.participant.dto.ParticipantResponse;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.common.ChallengeFullException;
import com.booster.shared.common.ResourceNotFoundException;
import com.booster.shared.common.UnauthorizedException;
import com.booster.shared.contract.CoinService;
import com.booster.shared.contract.CoinTransactionReason;
import com.booster.team.service.TeamFormationService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ParticipationService {

    private final ChallengeRepository challengeRepository;
    private final ChallengeParticipantRepository participantRepository;
    private final CoinService coinService;
    private final TeamFormationService teamFormationService;

    @Transactional
    public ParticipantResponse requestParticipation(Long userId, Long challengeId, ParticipationRequest request) {
        // Pessimistic lock to prevent race condition on participant count
        Challenge challenge = challengeRepository.findByIdWithLock(challengeId)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge", challengeId));

        if (challenge.getStatus() != ChallengeStatus.RECRUITING) {
            throw new IllegalStateException("Challenge is not in RECRUITING status");
        }

        if (participantRepository.findByChallengeIdAndUserId(challengeId, userId).isPresent()) {
            throw new IllegalStateException("Already applied to this challenge");
        }

        long confirmedCount = participantRepository.countByChallengeIdAndStatus(challengeId, ParticipantStatus.CONFIRMED);
        if (confirmedCount >= challenge.getMaxParticipants()) {
            throw new ChallengeFullException(challengeId);
        }

        log.info("Participation requested: userId={}, challengeId={}, approvalType={}", userId, challengeId, challenge.getApprovalType());

        // Coin deduction (atomic — throws InsufficientCoinException if balance is low)
        coinService.deduct(userId, challenge.getDepositCoins(), CoinTransactionReason.CHALLENGE_DEPOSIT, challengeId);

        ParticipantStatus initialStatus = (challenge.getApprovalType() == ApprovalType.AUTO)
                ? ParticipantStatus.CONFIRMED
                : ParticipantStatus.PENDING;

        ChallengeParticipant participant = ChallengeParticipant.builder()
                .challenge(challenge)
                .userId(userId)
                .personalStatement(request.getPersonalStatement())
                .gpsLat(request.getGpsLat())
                .gpsLng(request.getGpsLng())
                .gpsRadiusMeters(request.getGpsRadiusMeters())
                .gpsPlaceName(request.getGpsPlaceName())
                .gpsLocked(false)
                .status(initialStatus)
                .build();

        if (initialStatus == ParticipantStatus.CONFIRMED) {
            participant.confirm(LocalDateTime.now());
            log.info("Participant confirmed: userId={}, challengeId={}", userId, challengeId);
        }

        participantRepository.save(participant);

        if (initialStatus == ParticipantStatus.CONFIRMED) {
            teamFormationService.formTeamsIfReady(challengeId);
        }

        return ParticipantResponse.from(participant);
    }

    @Transactional
    public ParticipantResponse approveParticipation(Long leaderId, Long challengeId, Long participantId) {
        Challenge challenge = challengeRepository.findByIdWithLock(challengeId)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge", challengeId));

        if (!challenge.getCreatedBy().equals(leaderId)) {
            throw new UnauthorizedException("Only the challenge creator can approve participants");
        }

        ChallengeParticipant participant = participantRepository.findById(participantId)
                .orElseThrow(() -> new ResourceNotFoundException("Participant", participantId));

        if (participant.getStatus() != ParticipantStatus.PENDING) {
            throw new IllegalStateException("Participant is not in PENDING status");
        }

        long confirmedCount = participantRepository.countByChallengeIdAndStatus(challengeId, ParticipantStatus.CONFIRMED);
        if (confirmedCount >= challenge.getMaxParticipants()) {
            throw new ChallengeFullException(challengeId);
        }

        participant.confirm(LocalDateTime.now());
        log.info("Participant approved: participantId={}, challengeId={}, approvedBy={}", participantId, challengeId, leaderId);
        teamFormationService.formTeamsIfReady(challengeId);

        return ParticipantResponse.from(participant);
    }

    @Transactional
    public void cancelParticipation(Long userId, Long challengeId) {
        Challenge challenge = challengeRepository.findById(challengeId)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge", challengeId));

        if (challenge.getStatus() != ChallengeStatus.RECRUITING) {
            throw new IllegalStateException("Cannot cancel after challenge has started");
        }

        ChallengeParticipant participant = participantRepository.findByChallengeIdAndUserId(challengeId, userId)
                .orElseThrow(() -> new ResourceNotFoundException("Participation not found"));

        if (participant.getStatus() == ParticipantStatus.CONFIRMED) {
            coinService.credit(userId, challenge.getDepositCoins(), CoinTransactionReason.DEPOSIT_CANCEL_REFUND, challengeId);
        }

        participant.cancel();
        log.info("Participation cancelled: userId={}, challengeId={}", userId, challengeId);
    }
}
