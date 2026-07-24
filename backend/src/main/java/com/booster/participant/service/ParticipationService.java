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

        if (challenge.getStatus() != ChallengeStatus.READY) {
            throw new IllegalStateException("Challenge is not in READY status");
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

        if (challenge.getStatus() != ChallengeStatus.READY) {
            throw new IllegalStateException("Cannot approve participants after challenge has started");
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
        // (BS-39 I13) 챌린지 비관락으로 동시 취소를 직렬화한다. 예전엔 findById(무락)이라
        // 같은 유저의 동시 취소 요청이 둘 다 status=CONFIRMED/PENDING 을 읽고 각각 환불 →
        // 코인이 무에서 생성되는 이중 환불(코인 파밍)이 재현됐다. requestParticipation 과
        // 동일하게 findByIdWithLock 으로 잠그면, 먼저 취소한 트랜잭션이 상태를 CANCELLED 로
        // 커밋한 뒤에야 다음 취소가 진입해 재환불하지 않는다.
        Challenge challenge = challengeRepository.findByIdWithLock(challengeId)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge", challengeId));

        if (challenge.getStatus() != ChallengeStatus.READY) {
            throw new IllegalStateException("Cannot cancel after challenge has started");
        }

        ChallengeParticipant participant = participantRepository.findByChallengeIdAndUserId(challengeId, userId)
                .orElseThrow(() -> new ResourceNotFoundException("Participation not found"));

        // (BS-39 I10) 보증금 환불. 참여 시 코인은 AUTO/LEADER 관계없이 무조건 차감되므로
        // (requestParticipation), 아직 보증금을 쥔 상태(PENDING·CONFIRMED)면 모두 환불해야 한다.
        // 예전엔 CONFIRMED만 환불해 LEADER 승인형의 PENDING 참여자가 취소 시 보증금을 잃었다.
        // CANCELLED/LEFT/REJECTED(이미 종료·환불된 상태)는 재환불하지 않는다.
        if (participant.getStatus() == ParticipantStatus.CONFIRMED
                || participant.getStatus() == ParticipantStatus.PENDING) {
            coinService.credit(userId, challenge.getDepositCoins(), CoinTransactionReason.DEPOSIT_CANCEL_REFUND, challengeId);
        }

        participant.cancel();
        log.info("Participation cancelled: userId={}, challengeId={}", userId, challengeId);
    }
}
