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
    private final SettlementFailureRecorder failureRecorder;

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
        if (existing.isPresent()) {
            SettlementStatus status = existing.get().getStatus();
            if (status == SettlementStatus.COMPLETED || status == SettlementStatus.PENDING) {
                log.info("Settlement already in progress or completed for challengeId={}", challengeId);
                return;
            }
        }

        // PENDING row 선점: unique constraint가 동시 호출을 직렬화하는 포인트
        Settlement settlement;
        try {
            settlement = existing.orElseGet(() -> settlementRepository.save(
                    Settlement.builder().challengeId(challengeId).status(SettlementStatus.PENDING).build()
            ));
        } catch (DataIntegrityViolationException e) {
            log.warn("Concurrent settlement attempt for challengeId={}, skipping", challengeId);
            return;
        }

        try {
            List<Team> teams = teamRepository.findByChallengeId(challengeId);
            if (teams.size() < 2) {
                throw new IllegalStateException("Challenge must have 2 teams for settlement: " + challengeId);
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
            // REQUIRES_NEW 별도 트랜잭션으로 FAILED 상태 저장 — 외부 롤백에 영향받지 않음
            failureRecorder.recordFailure(challengeId);
            throw e;
        }
    }
}
