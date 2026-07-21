package com.booster.concurrency;

import com.booster.challenge.domain.ApprovalType;
import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.domain.ChallengeVisibility;
import com.booster.challenge.domain.VerificationType;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.challengecheckin.service.ChallengeCheckInService;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.domain.ParticipantStatus;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.team.domain.Team;
import com.booster.team.repository.TeamRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * [C9] 팀 참여율(participation_rate) 동시 갱신 시 Lost Update.
 *
 * <p>같은 팀의 CONFIRMED 참여자 N명이 <b>동시에</b> 체크인하면, 각 체크인이
 * {@code updateTeamParticipationRate} 를 통해 "커밋된 성공 체크인 수 / 팀원 수" 로 팀의
 * participation_rate 를 read-modify-write 한다. 이 경로가 서로 다른 인스턴스/스레드에서
 * 겹치면(멀티서버) 마지막 writer 가 이전 writer 의 갱신을 덮어써(last-writer-wins) 최종
 * participation_rate 가 실제 성공 수보다 낮게 남는다 = Lost Update.
 *
 * <p><b>RED(without @Version)</b>: Team 에 낙관적 락이 없으면 두 트랜잭션이 같은 버전을 읽고
 * 각자 계산한 값을 덮어써 최종값이 1.00 미만으로 남는다 → 이 단언이 실패한다.
 * <br><b>GREEN(with @Version + 재시도)</b>: 커밋 시 버전 충돌이
 * {@code ObjectOptimisticLockingFailureException} 으로 감지되고, 별도 트랜잭션에서 최신
 * 상태를 re-read 하여 재계산·재저장하므로 최종 participation_rate 가 정확히 반영된다.
 */
class C9ParticipationRateLostUpdateTest extends ConcurrencyTestBase {

    @Autowired ChallengeCheckInService challengeCheckInService;
    @Autowired ChallengeRepository challengeRepository;
    @Autowired ChallengeParticipantRepository participantRepository;
    @Autowired TeamRepository teamRepository;

    /**
     * 한 팀 동시 작성자 수. 5:5 팀 구성상 한 팀 최대 인원(5)을 상한으로 본다.
     * ChallengeCheckInService 의 낙관락 재시도 상한이 이 값 이상이어야 GREEN 이 수렴한다.
     */
    private static final int MEMBERS = 5;

    /**
     * 동시성 인터리빙은 비결정적이므로 신규 팀으로 다수 라운드를 돌린다.
     * 낙관적 락이 없으면 어느 한 라운드에서 stale writer 가 마지막으로 덮어써 최종
     * participation_rate 가 1.00 미만으로 남는다(= Lost Update, RED).
     */
    private static final int ROUNDS = 12;

    @Test
    @DisplayName("같은 팀 동시 체크인 시 최종 participation_rate 는 모든 기여를 반영해야 한다(Lost Update 금지)")
    void concurrentCheckIns_participationRateMustNotLoseUpdate() throws Exception {
        for (int round = 0; round < ROUNDS; round++) {
            runOneRound(round);
        }
    }

    private void runOneRound(int round) throws InterruptedException {
        // --- 픽스처: ACTIVE 챌린지 + 팀 1개 + 같은 팀 CONFIRMED 참여자 N명 (각 저장이 자기 트랜잭션에서 커밋) ---
        Challenge challenge = challengeRepository.save(Challenge.builder()
                .category("HEALTH")
                .title("C9 동시 참여율 r" + round)
                .verificationType(VerificationType.GPS)
                .durationDays(7)
                .depositCoins(100L)
                .visibility(ChallengeVisibility.PUBLIC)
                .approvalType(ApprovalType.AUTO)
                .status(ChallengeStatus.ACTIVE)
                .maxParticipants(10)
                .createdBy(1L)
                .build());
        Long challengeId = challenge.getId();

        Team team = teamRepository.save(Team.builder()
                .challengeId(challengeId)
                .name("C9-TEAM-r" + round)
                .initialMemberCount(MEMBERS)
                .build());
        Long teamId = team.getId();

        List<Long> userIds = new ArrayList<>();
        for (int i = 0; i < MEMBERS; i++) {
            Long userId = newUserWithLocation("c9-");
            participantRepository.save(ChallengeParticipant.builder()
                    .challenge(challenge)
                    .userId(userId)
                    .teamId(teamId)
                    .status(ParticipantStatus.CONFIRMED)
                    .gpsLat(LAT)
                    .gpsLng(LNG)
                    .gpsRadiusMeters(100)
                    .gpsLocked(true)
                    .build());
            userIds.add(userId);
        }

        // --- 같은 팀 N명이 동일 좌표(반경 내 → SUCCESS)로 일제히 체크인 ---
        List<Runnable> tasks = new ArrayList<>();
        for (Long userId : userIds) {
            tasks.add(() -> challengeCheckInService.recordCheckIn(userId, challengeId, LAT, LNG));
        }
        List<Throwable> errors = runConcurrently(tasks);

        assertThat(errors)
                .as("round %d: 동시 체크인 중 예외가 없어야 한다: %s", round, errors)
                .isEmpty();

        // 모든 성공 체크인이 반영되면 rate = 성공 수(N) / 팀원 수(N) = 1.00.
        Team reloaded = teamRepository.findById(teamId).orElseThrow();
        assertThat(reloaded.getParticipationRate())
                .as("round %d: 최종 participation_rate 는 모든 동시 성공 체크인을 반영해야 한다(Lost Update 금지)", round)
                .isEqualByComparingTo(BigDecimal.ONE);
    }
}
