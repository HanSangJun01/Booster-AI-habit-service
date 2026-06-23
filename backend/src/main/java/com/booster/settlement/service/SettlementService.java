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
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

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
            return; // 멱등성 — 이미 정산됐거나 상태 불일치 시 no-op
        }

        // ENDED → SETTLED 전이 (동시 호출 시 두 번째 호출은 IllegalStateException으로 차단됨)
        challenge.markSettled();
        challengeRepository.save(challenge);

        Settlement settlement = settlementRepository.findByChallengeId(challengeId)
                .orElseGet(() -> Settlement.builder()
                        .challengeId(challengeId)
                        .status(SettlementStatus.PENDING)
                        .build());

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

            log.info("Settlement result: challengeId={}, teamA={} ({}), teamB={} ({})", challengeId, teamA.getId(), resultA, teamB.getId(), resultB);

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
                // WIN/LOSE: 승팀 참여자에게 totalPool 균등 지급
                Team winnerTeam = (resultA == TeamResult.WIN) ? teamA : teamB;
                Team loserTeam = (resultA == TeamResult.LOSE) ? teamA : teamB;
                winnerTeamId = winnerTeam.getId();
                loserTeamId = loserTeam.getId();

                List<ChallengeParticipant> winnerParticipants = participantRepository
                        .findByTeamId(winnerTeamId).stream()
                        .filter(p -> p.getStatus() == ParticipantStatus.CONFIRMED)
                        .toList();

                if (!winnerParticipants.isEmpty()) {
                    perWinnerPayout = totalPool / winnerParticipants.size();
                    for (ChallengeParticipant p : winnerParticipants) {
                        coinService.credit(p.getUserId(), perWinnerPayout,
                                CoinTransactionReason.SETTLEMENT_WIN, challengeId);
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
            settlement.fail();
            settlementRepository.save(settlement);
        }
    }

}
