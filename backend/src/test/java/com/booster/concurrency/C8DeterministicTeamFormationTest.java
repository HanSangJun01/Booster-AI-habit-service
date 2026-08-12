package com.booster.concurrency;

import com.booster.challenge.domain.ApprovalType;
import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.domain.ChallengeVisibility;
import com.booster.challenge.domain.VerificationType;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.domain.ParticipantStatus;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.team.domain.Team;
import com.booster.team.repository.TeamRepository;
import com.booster.team.service.TeamFormationService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * [멀티서버 확장 P2] {@code TeamFormationService.formTeamsIfReady} 의 팀 배정 셔플 결정성.
 *
 * <p>기존 {@code Collections.shuffle(shuffled)} 는 시드 없는 난수를 사용해, 같은 challengeId 에
 * 대해 어느 인스턴스(또는 같은 인스턴스라도 다른 시각)가 팀을 구성하느냐에 따라 A/B 배정이
 * 달라질 수 있었다. 멀티서버 환경에서는 재시도·장애조치로 같은 challengeId 의 팀 구성이 다른
 * 인스턴스에서 수행될 여지가 있으므로, 배정 결과가 challengeId 에 대해 결정적이어야 한다.
 *
 * <p>{@code existsByChallengeId} 가드 때문에 같은 challengeId 로 두 번째 호출은 no-op 이 된다.
 * 따라서 1차 팀구성 후 teams/배정을 리셋(삭제/필드 초기화)한 뒤 같은 challengeId 로 재호출해,
 * 같은 입력(participant 목록)에 대해 같은 challengeId 시드로 다시 셔플했을 때 결과가 동일한지
 * 검증한다. 절대 teamId 는 재구성 시 새로 채번되어 달라지므로, 비교는 팀 "이름"(A팀/B팀) 기준
 * 상대 배정으로 한다.
 */
class C8DeterministicTeamFormationTest extends ConcurrencyTestBase {

    @Autowired private TeamFormationService teamFormationService;
    @Autowired private ChallengeRepository challengeRepository;
    @Autowired private ChallengeParticipantRepository participantRepository;
    @Autowired private TeamRepository teamRepository;

    @Test
    @DisplayName("같은 challengeId 로 팀구성을 두 번 수행해도 참여자별 A/B 배정이 동일해야 한다")
    void formTeamsIfReady_sameChallenge_twice_yieldsIdenticalAssignment() {
        Long challengeId = newReadyChallenge();
        newConfirmedParticipants(challengeId, 10);

        teamFormationService.formTeamsIfReady(challengeId);
        Map<Long, String> firstAssignment = assignmentByTeamName(challengeId);

        resetTeams(challengeId);

        teamFormationService.formTeamsIfReady(challengeId);
        Map<Long, String> secondAssignment = assignmentByTeamName(challengeId);

        assertThat(secondAssignment)
                .as("같은 challengeId 로 두 번 팀을 구성해도 참여자별 배정(A팀/B팀)이 동일해야 한다")
                .isEqualTo(firstAssignment);
    }

    // ---- 픽스처 ----------------------------------------------------------

    private Long newReadyChallenge() {
        Challenge challenge = challengeRepository.save(Challenge.builder()
                .category("habit")
                .title("C8 결정성 테스트")
                .verificationType(VerificationType.GPS)
                .durationDays(7)
                .depositCoins(0)
                .visibility(ChallengeVisibility.PRIVATE)
                .approvalType(ApprovalType.AUTO)
                .status(ChallengeStatus.READY)
                .maxParticipants(10)
                .createdBy(1L)
                .build());
        return challenge.getId();
    }

    /** user_id 는 challenge_participants 에 FK 가 없어(V1 마이그레이션) 임의 id 로 충분하다. */
    private void newConfirmedParticipants(Long challengeId, int count) {
        Challenge challengeRef = challengeRepository.getReferenceById(challengeId);
        for (int i = 0; i < count; i++) {
            long userId = -1L * SEQ.incrementAndGet() * 1000 - i;
            participantRepository.save(ChallengeParticipant.builder()
                    .challenge(challengeRef)
                    .userId(userId)
                    .status(ParticipantStatus.CONFIRMED)
                    .gpsLocked(false)
                    .build());
        }
    }

    /** userId -> 팀이름(A팀/B팀) 매핑. */
    private Map<Long, String> assignmentByTeamName(Long challengeId) {
        Map<Long, String> teamNameById = teamRepository.findByChallengeId(challengeId).stream()
                .collect(Collectors.toMap(Team::getId, Team::getName));

        List<ChallengeParticipant> confirmed = participantRepository
                .findByChallengeIdAndStatus(challengeId, ParticipantStatus.CONFIRMED);

        Map<Long, String> result = new LinkedHashMap<>();
        for (ChallengeParticipant p : confirmed) {
            result.put(p.getUserId(), teamNameById.get(p.getTeamId()));
        }
        return result;
    }

    /** 재실행을 위해 팀을 삭제하고 참여자 배정 필드를 초기화한다(formTeamsIfReady 는 teams 존재 시 no-op). */
    private void resetTeams(Long challengeId) {
        inTransaction(() -> {
            List<Team> teams = new ArrayList<>(teamRepository.findByChallengeId(challengeId));
            teamRepository.deleteAll(teams);
            em.createQuery("UPDATE ChallengeParticipant p SET p.teamId = null, p.gpsLocked = false, "
                            + "p.activeUntil = null WHERE p.challenge.id = :cid AND p.status = 'CONFIRMED'")
                    .setParameter("cid", challengeId)
                    .executeUpdate();
        });
        em.clear();
    }
}
