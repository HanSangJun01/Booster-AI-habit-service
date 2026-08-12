package com.booster.settlement.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.challengecheckin.service.ParticipationRateCalculator;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.domain.ParticipantStatus;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.settlement.domain.Settlement;
import com.booster.settlement.domain.SettlementStatus;
import com.booster.settlement.repository.SettlementRepository;
import com.booster.shared.common.ResourceNotFoundException;
import com.booster.shared.contract.CoinService;
import com.booster.shared.contract.CoinTransactionReason;
import com.booster.team.domain.Team;
import com.booster.team.domain.TeamResult;
import com.booster.team.repository.TeamRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import com.booster.shared.common.BusinessException;

@Slf4j
@Service
@RequiredArgsConstructor
public class SettlementService {

    private final ChallengeRepository challengeRepository;
    private final TeamRepository teamRepository;
    private final ChallengeParticipantRepository participantRepository;
    private final SettlementRepository settlementRepository;
    private final CoinService coinService;
    private final ParticipationRateCalculator participationRateCalculator;

    @Transactional
    public void settleChallenge(Long challengeId) {
        log.info("Settlement started: challengeId={}", challengeId);
        Challenge challenge = challengeRepository.findById(challengeId)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge not found: " + challengeId));

        if (challenge.getStatus() != ChallengeStatus.ENDED) {
            return;
        }

        // Idempotency gate: COMPLETED 또는 PENDING 모두 skip (이중 지급 방지)
        Optional<Settlement> existing = settlementRepository.findByChallengeId(challengeId);
        Settlement settlement;
        if (existing.isPresent()) {
            SettlementStatus status = existing.get().getStatus();
            if (status == SettlementStatus.COMPLETED || status == SettlementStatus.PENDING) {
                log.info("Settlement already in progress or completed for challengeId={}", challengeId);
                return;
            }

            // [이중지급 차단] 재시도 경로(FAILED): 기존 행은 INSERT가 없어 unique 제약이 걸리지
            // 않는다 → 두 호출자가 동시에 게이트를 통과해 코인을 이중 지급할 수 있다. FAILED→PENDING
            // 원자적 CAS로 오직 한 호출자만 재시도 소유권을 얻게 직렬화한다. 0이면 이미 선점당함.
            int claimed = settlementRepository.claimFailedForRetry(challengeId);
            if (claimed == 0) {
                log.info("다른 호출자가 이미 재시도를 선점함, skip: challengeId={}", challengeId);
                return;
            }
            settlement = existing.get();
        } else {
            // 신규 정산: PENDING row INSERT — unique(challenge_id)가 동시 INSERT를 직렬화하는 포인트
            try {
                settlement = settlementRepository.save(
                        Settlement.builder().challengeId(challengeId).status(SettlementStatus.PENDING).build()
                );
            } catch (DataIntegrityViolationException e) {
                log.warn("Concurrent settlement attempt for challengeId={}, skipping", challengeId);
                return;
            }
        }

        try {
            List<Team> teams = teamRepository.findByChallengeId(challengeId);
            if (teams.size() < 2) {
                throw BusinessException.conflict("TEAMS_NOT_FORMED",
                        "정산하려면 팀이 2개여야 합니다: challengeId=" + challengeId);
            }

            Team teamA = teams.get(0);
            Team teamB = teams.get(1);

            BigDecimal rateA = participationRateCalculator.authoritativeRate(challengeId, teamA.getId());
            BigDecimal rateB = participationRateCalculator.authoritativeRate(challengeId, teamB.getId());

            // WIN/LOSE/DRAW 판정
            TeamResult resultA;
            TeamResult resultB;
            int cmp = rateA.compareTo(rateB);
            if (cmp > 0) {
                resultA = TeamResult.WIN;
                resultB = TeamResult.LOSE;
            } else if (cmp < 0) {
                resultA = TeamResult.LOSE;
                resultB = TeamResult.WIN;
            } else {
                resultA = TeamResult.DRAW;
                resultB = TeamResult.DRAW;
            }

            log.info("Settlement result: challengeId={}, teamA={} ({}), teamB={} ({})",
                    challengeId, teamA.getId(), resultA, teamB.getId(), resultB);

            // 전체 참여자 (CONFIRMED + LEFT) 조회
            List<ChallengeParticipant> allParticipants = participantRepository
                    .findByChallengeIdAndStatus(challengeId, ParticipantStatus.CONFIRMED);
            allParticipants.addAll(participantRepository
                    .findByChallengeIdAndStatus(challengeId, ParticipantStatus.LEFT));

            long totalPool = challenge.getDepositCoins() * allParticipants.size();

            Long winnerTeamId = null;
            Long loserTeamId = null;
            long perWinnerPayout = 0L;
            boolean isDraw = (resultA == TeamResult.DRAW);

            if (isDraw) {
                // DRAW: CONFIRMED 참여자에게만 예치금 반환 (LEFT 참여자 제외)
                for (ChallengeParticipant p : allParticipants) {
                    if (p.getStatus() == ParticipantStatus.CONFIRMED) {
                        coinService.credit(p.getUserId(), challenge.getDepositCoins(),
                                CoinTransactionReason.DEPOSIT_REFUND, challengeId);
                    }
                }
            } else {
                // WIN/LOSE: 승팀 CONFIRMED 참여자에게 totalPool 지급
                Team winnerTeam = (resultA == TeamResult.WIN) ? teamA : teamB;
                Team loserTeam = (resultA == TeamResult.LOSE) ? teamA : teamB;
                winnerTeamId = winnerTeam.getId();
                loserTeamId = loserTeam.getId();

                List<ChallengeParticipant> winnerParticipants = participantRepository
                        .findByTeamId(winnerTeamId).stream()
                        .filter(p -> p.getStatus() == ParticipantStatus.CONFIRMED)
                        .toList();

                if (!winnerParticipants.isEmpty()) {
                    // 나머지 코인은 첫 번째 승자에게 추가 지급 (잔액 소실 방지)
                    perWinnerPayout = totalPool / winnerParticipants.size();
                    long remainder = totalPool % winnerParticipants.size();
                    for (int i = 0; i < winnerParticipants.size(); i++) {
                        long payout = (i == 0) ? perWinnerPayout + remainder : perWinnerPayout;
                        coinService.credit(winnerParticipants.get(i).getUserId(), payout,
                                CoinTransactionReason.SETTLEMENT_WIN, challengeId);
                    }
                } else {
                    // 승팀 전원 LEFT → CONFIRMED 참여자에게 예치금 환불
                    for (ChallengeParticipant p : allParticipants) {
                        if (p.getStatus() == ParticipantStatus.CONFIRMED) {
                            coinService.credit(p.getUserId(), challenge.getDepositCoins(),
                                    CoinTransactionReason.DEPOSIT_REFUND, challengeId);
                        }
                    }
                }
            }

            // Team 결과 및 참여율 업데이트
            teamA.setResult(resultA);
            teamA.updateParticipationRate(rateA);
            teamRepository.save(teamA);

            teamB.setResult(resultB);
            teamB.updateParticipationRate(rateB);
            teamRepository.save(teamB);

            settlement.complete(LocalDateTime.now(), totalPool, perWinnerPayout,
                    winnerTeamId, loserTeamId, isDraw);
            settlementRepository.save(settlement);
            log.info("Settlement completed: challengeId={}, totalPool={}", challengeId, totalPool);

        } catch (Exception e) {
            log.error("Settlement failed for challengeId={}", challengeId, e);
            // [교착 수정] 여기서 REQUIRES_NEW로 FAILED를 기록하면 안 된다:
            // 이 트랜잭션이 위에서 INSERT한 PENDING 행(unique challenge_id)이 아직 미커밋인
            // 상태에서, 같은 스레드의 새 트랜잭션이 동일 challenge_id를 INSERT하려다
            // 자기 자신의 락을 영원히 기다리는 self-deadlock이 발생한다(스케줄러 스레드 사망).
            // FAILED 기록은 호출자(ChallengeEndScheduler)가 이 트랜잭션 롤백 후 수행한다.
            throw e;
        }
    }
}
