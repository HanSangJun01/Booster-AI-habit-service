package com.booster.social.service;

import com.booster.challengecheckin.domain.CheckInStatus;
import com.booster.challengecheckin.repository.ChallengeCheckInRepository;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.domain.ParticipantStatus;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.social.dto.LeaderboardEntry;
import com.booster.team.domain.Team;
import com.booster.team.repository.TeamRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

@Service
@Transactional(readOnly = true)
@RequiredArgsConstructor
public class LeaderboardService {

    private final ChallengeCheckInRepository checkInRepository;
    private final ChallengeParticipantRepository participantRepository;
    private final TeamRepository teamRepository;

    public List<LeaderboardEntry> getPersonalLeaderboard(Long challengeId) {
        List<ChallengeParticipant> participants =
                participantRepository.findByChallengeIdAndStatus(challengeId, ParticipantStatus.CONFIRMED);

        List<LeaderboardEntry> entries = new ArrayList<>();
        for (ChallengeParticipant p : participants) {
            long count = checkInRepository.countByParticipantIdAndStatus(p.getId(), CheckInStatus.SUCCESS);
            entries.add(LeaderboardEntry.builder()
                    .userId(p.getUserId())
                    .teamId(p.getTeamId())
                    .checkInCount(count)
                    .participationRate(BigDecimal.ZERO)
                    .build());
        }

        entries.sort(Comparator.comparingLong(LeaderboardEntry::getCheckInCount).reversed());

        List<LeaderboardEntry> ranked = new ArrayList<>();
        for (int i = 0; i < entries.size(); i++) {
            LeaderboardEntry e = entries.get(i);
            ranked.add(LeaderboardEntry.builder()
                    .rank(i + 1)
                    .userId(e.getUserId())
                    .teamId(e.getTeamId())
                    .name(e.getName())
                    .checkInCount(e.getCheckInCount())
                    .participationRate(e.getParticipationRate())
                    .build());
        }
        return ranked;
    }

    public List<LeaderboardEntry> getTeamLeaderboard(Long challengeId) {
        List<Team> teams = teamRepository.findByChallengeId(challengeId);

        teams.sort(Comparator.comparing(Team::getParticipationRate).reversed());

        List<LeaderboardEntry> ranked = new ArrayList<>();
        for (int i = 0; i < teams.size(); i++) {
            Team t = teams.get(i);
            ranked.add(LeaderboardEntry.builder()
                    .rank(i + 1)
                    .teamId(t.getId())
                    .name(t.getName())
                    .checkInCount(0L)
                    .participationRate(t.getParticipationRate())
                    .build());
        }
        return ranked;
    }
}
