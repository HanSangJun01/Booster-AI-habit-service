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
import java.util.List;

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
        List<ChallengeParticipant> confirmed = participantRepository
                .findByChallengeIdAndStatus(challengeId, ParticipantStatus.CONFIRMED);

        log.info("Team formation check: challengeId={}, confirmedCount={}", challengeId, confirmed.size());

        if (confirmed.size() < TEAM_SIZE * 2) {
            log.debug("Not enough participants yet: challengeId={}, count={}", challengeId, confirmed.size());
            return;
        }

        log.info("Forming teams for challenge {}", challengeId);

        List<ChallengeParticipant> shuffled = new ArrayList<>(confirmed);
        Collections.shuffle(shuffled);

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

    @Transactional(readOnly = true)
    public List<TeamResponse> getTeams(Long challengeId) {
        return teamRepository.findByChallengeId(challengeId).stream()
                .map(TeamResponse::from)
                .toList();
    }
}
