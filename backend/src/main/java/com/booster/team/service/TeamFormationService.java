package com.booster.team.service;

import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.domain.ParticipantStatus;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.team.domain.Team;
import com.booster.team.dto.TeamResponse;
import com.booster.team.repository.TeamRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Random;

@Slf4j
@Service
@RequiredArgsConstructor
public class TeamFormationService {

    private static final int TEAM_SIZE = 5;

    private final TeamRepository teamRepository;
    private final ChallengeParticipantRepository participantRepository;
    private final ChallengeLifecycleService lifecycleService;

    /**
     * 10번째 참여자 확정 트랜잭션 내에서 동기 호출.
     * 정원 미충족 시 no-op. 충족 시 팀 구성 + 챌린지 시작.
     */
    @Transactional
    public void formTeamsIfReady(Long challengeId) {
        if (teamRepository.existsByChallengeId(challengeId)) {
            log.debug("Teams already formed for challengeId={}, skipping", challengeId);
            return;
        }

        List<ChallengeParticipant> confirmed = participantRepository
                .findByChallengeIdAndStatus(challengeId, ParticipantStatus.CONFIRMED);

        log.info("Team formation check: challengeId={}, confirmedCount={}", challengeId, confirmed.size());

        if (confirmed.size() < TEAM_SIZE * 2) {
            log.debug("Not enough participants yet: challengeId={}, count={}", challengeId, confirmed.size());
            return;
        }

        log.info("Forming teams for challenge {}", challengeId);

        // 결정적 배정 — 어느 인스턴스가 실행해도 동일 결과 (시드=challengeId)
        List<ChallengeParticipant> shuffled = orderForAssignment(confirmed, challengeId);

        Team teamA = teamRepository.save(Team.builder()
                .challengeId(challengeId)
                .name("A팀")
                .initialMemberCount(TEAM_SIZE)
                .build());

        Team teamB = teamRepository.save(Team.builder()
                .challengeId(challengeId)
                .name("B팀")
                .initialMemberCount(TEAM_SIZE)
                .build());

        var endedAt = lifecycleService.startChallenge(challengeId);

        for (int i = 0; i < shuffled.size(); i++) {
            Long teamId = (i < TEAM_SIZE) ? teamA.getId() : teamB.getId();
            shuffled.get(i).assignTeam(teamId, endedAt);
        }

        log.info("Teams formed: teamA={} teamB={}", teamA.getId(), teamB.getId());
    }

    /**
     * 팀 배정용 참여자 순서를 결정적으로 만든다.
     *
     * <p>{@code findByChallengeIdAndStatus} 는 ORDER BY 가 없어 DB row 순서가 비보장이다.
     * seed 셔플만으로는 <em>입력 순서</em>가 인스턴스마다 다르면 결과도 달라진다. 따라서 먼저
     * id 로 안정 정렬해 입력 순서를 고정한 뒤 seed(=challengeId) 셔플을 적용해야, 크로스
     * 인스턴스 결정성(어느 인스턴스가 실행해도 동일 A/B 배정)이 성립한다.
     */
    static List<ChallengeParticipant> orderForAssignment(List<ChallengeParticipant> confirmed, long seed) {
        List<ChallengeParticipant> ordered = new ArrayList<>(confirmed);
        ordered.sort(Comparator.comparing(ChallengeParticipant::getId)); // 안정 입력순서 고정
        Collections.shuffle(ordered, new Random(seed));                  // seed=challengeId 결정적 셔플
        return ordered;
    }

    @Transactional(readOnly = true)
    public List<TeamResponse> getTeams(Long challengeId) {
        return teamRepository.findByChallengeId(challengeId).stream()
                .map(TeamResponse::from)
                .toList();
    }
}
