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
import java.util.List;
import com.booster.shared.common.BusinessException;

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
            throw BusinessException.conflict("CHALLENGE_NOT_READY", "모집이 끝난 챌린지입니다.");
        }

        if (participantRepository.findByChallengeIdAndUserId(challengeId, userId).isPresent()) {
            throw BusinessException.conflict("ALREADY_APPLIED", "이미 참가 신청한 챌린지입니다.");
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

    /**
     * 참가자 목록 조회.
     *
     * <p>없을 때 방장은 누가 신청했는지 볼 수 없었고, 승인 API 가 요구하는 {@code participantId} 를
     * 얻을 방법이 없어 <b>방장 승인(approvalType=LEADER) 기능이 사실상 작동하지 않았다.</b>
     *
     * <p>★권한: 방장 또는 CONFIRMED 참여자만. 아무나 조회하면 남의 챌린지 참가자 명단이
     * 통째로 노출된다(BS-39 I2 팀채팅 / I14 체크인 열람과 동일 계열).
     *
     * @param status null 이면 전체, 지정하면 해당 상태만(방장 화면은 보통 PENDING)
     */
    @Transactional(readOnly = true)
    public List<ParticipantResponse> getParticipants(Long userId, Long challengeId, ParticipantStatus status) {
        Challenge challenge = challengeRepository.findById(challengeId)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge", challengeId));

        boolean isLeader = challenge.getCreatedBy().equals(userId);
        boolean isMember = participantRepository
                .findConfirmedByUserAndChallenge(challengeId, userId).isPresent();
        if (!isLeader && !isMember) {
            throw new UnauthorizedException("Not a participant of this challenge");
        }

        List<ChallengeParticipant> participants = (status == null)
                ? participantRepository.findByChallengeIdOrderByIdAsc(challengeId)
                : participantRepository.findByChallengeIdAndStatus(challengeId, status);

        return participants.stream().map(ParticipantResponse::from).toList();
    }

    /**
     * 챌린지 생성자를 CONFIRMED 참가자로 등록한다 (챌린지 생성 트랜잭션 안에서 호출).
     *
     * <p>예전에는 생성과 참가가 분리돼 있어 방장이 자기 챌린지의 참가자가 아니었다. 그 결과
     * 방장은 자기 챌린지에서 인증을 못 하고, 정원 인원수에도 잡히지 않아 10명 채우기가 더
     * 어려웠으며, 참가하려면 공개 탐색에서 자기 챌린지를 찾아 다시 신청해야 했다.
     *
     * <p>{@code requestParticipation} 과 달리 <b>approvalType 과 무관하게 항상 CONFIRMED</b> 다
     * (방장이 자기 자신을 승인할 일은 없다). 예치금은 동일하게 차감한다 — 방장만 공짜로
     * 참가하면 정산 풀({@code 예치금 × 참여자수})과 실제 징수액이 어긋난다.
     *
     * <p>생성과 같은 트랜잭션이므로 중간에 실패하면 챌린지도 함께 롤백된다 → "참가자가 없는
     * 빈 챌린지"가 남지 않는다(챌린지 삭제 API 가 없어 한 번 생기면 정리할 수 없다).
     */
    @Transactional
    public void registerCreatorAsParticipant(Challenge challenge, Long userId,
                                             ParticipationRequest request) {
        coinService.deduct(userId, challenge.getDepositCoins(),
                CoinTransactionReason.CHALLENGE_DEPOSIT, challenge.getId());

        ChallengeParticipant leader = ChallengeParticipant.builder()
                .challenge(challenge)
                .userId(userId)
                .personalStatement(request.getPersonalStatement())
                .gpsLat(request.getGpsLat())
                .gpsLng(request.getGpsLng())
                .gpsRadiusMeters(request.getGpsRadiusMeters())
                .gpsPlaceName(request.getGpsPlaceName())
                .gpsLocked(false)
                .status(ParticipantStatus.CONFIRMED)
                .build();
        leader.confirm(LocalDateTime.now());
        participantRepository.save(leader);

        log.info("Creator registered as participant: userId={}, challengeId={}", userId, challenge.getId());
    }

    @Transactional
    public ParticipantResponse approveParticipation(Long leaderId, Long challengeId, Long participantId) {
        Challenge challenge = challengeRepository.findByIdWithLock(challengeId)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge", challengeId));

        if (!challenge.getCreatedBy().equals(leaderId)) {
            throw new UnauthorizedException("Only the challenge creator can approve participants");
        }

        if (challenge.getStatus() != ChallengeStatus.READY) {
            throw BusinessException.conflict("CHALLENGE_ALREADY_STARTED", "챌린지가 시작된 뒤에는 승인할 수 없습니다.");
        }

        ChallengeParticipant participant = participantRepository.findById(participantId)
                .orElseThrow(() -> new ResourceNotFoundException("Participant", participantId));

        if (participant.getStatus() != ParticipantStatus.PENDING) {
            throw BusinessException.conflict("PARTICIPANT_NOT_PENDING", "승인 대기 상태의 참가자가 아닙니다.");
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
            throw BusinessException.conflict("CHALLENGE_ALREADY_STARTED", "챌린지가 시작된 뒤에는 취소할 수 없습니다.");
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

    /**
     * (BS-39 I15) 회원 탈퇴 시 아직 시작 전(READY) 챌린지의 참여를 환불·정리한다.
     * 예전엔 withdraw()가 user.deactivate()만 해서 탈퇴 후에도 CONFIRMED 참여와 예치금이 남아
     * 정산에 좀비 참여자로 집계되고 보증금이 영구 잠겼다. 취소 규칙과 동일하게 READY 챌린지만
     * 환불 대상이며(시작 후엔 예치금 확정 — cancelParticipation과 같은 규칙), 각 챌린지를
     * 비관락으로 잠가 동시 상태전이·이중환불과 경합하지 않는다(I13과 동일).
     */
    @Transactional
    public void cancelActiveParticipationsForWithdrawal(Long userId) {
        for (ChallengeParticipant p : participantRepository.findByUserId(userId)) {
            if (p.getStatus() != ParticipantStatus.PENDING && p.getStatus() != ParticipantStatus.CONFIRMED) {
                continue; // 이미 취소/종료·환불된 참여는 건너뜀
            }
            Long challengeId = p.getChallenge().getId();
            Challenge challenge = challengeRepository.findByIdWithLock(challengeId).orElse(null);
            if (challenge == null || challenge.getStatus() != ChallengeStatus.READY) {
                continue; // 시작(ACTIVE)/종료된 챌린지는 기존 취소규칙대로 환불 없음
            }
            // 락 획득 후 참여 상태를 다시 확인(그 사이 취소되었을 수 있음).
            ChallengeParticipant fresh = participantRepository
                    .findByChallengeIdAndUserId(challengeId, userId).orElse(null);
            if (fresh == null) {
                continue;
            }
            if (fresh.getStatus() == ParticipantStatus.CONFIRMED
                    || fresh.getStatus() == ParticipantStatus.PENDING) {
                coinService.credit(userId, challenge.getDepositCoins(),
                        CoinTransactionReason.DEPOSIT_CANCEL_REFUND, challengeId);
                fresh.cancel();
                log.info("Withdrawal cleanup: cancelled participation userId={}, challengeId={}", userId, challengeId);
            }
        }
    }
}
