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
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Slf4j
@Service
@Transactional(readOnly = true)
@RequiredArgsConstructor
public class LeaderboardService {

    private final ChallengeCheckInRepository checkInRepository;
    private final ChallengeParticipantRepository participantRepository;
    private final TeamRepository teamRepository;

    // 순위표는 강한 일관성이 필요 없는 조회이므로 트랜잭션을 걸지 않는다.
    // 각 리포지토리 호출이 커넥션을 개별 획득·즉시 반납하고, 정렬/조립은 커넥션 비점유 상태에서 수행 → 커넥션 점유시간 단축.
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    public List<LeaderboardEntry> getPersonalLeaderboard(Long challengeId) {
        log.debug("Personal leaderboard requested: challengeId={}", challengeId);
        List<ChallengeParticipant> participants =
                participantRepository.findByChallengeIdAndStatus(challengeId, ParticipantStatus.CONFIRMED);

        // 참가자별 SUCCESS 체크인 수를 단일 GROUP BY 쿼리로 집계 (참가자마다 count 하던 N+1 제거)
        Map<Long, Long> successCountByParticipant = checkInRepository
                .countByChallengeIdAndStatusGroupByParticipant(challengeId, CheckInStatus.SUCCESS)
                .stream()
                .collect(Collectors.toMap(
                        ChallengeCheckInRepository.ParticipantCheckInCount::getParticipantId,
                        ChallengeCheckInRepository.ParticipantCheckInCount::getCount));

        List<LeaderboardEntry> entries = new ArrayList<>();
        for (ChallengeParticipant p : participants) {
            long count = successCountByParticipant.getOrDefault(p.getId(), 0L);
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
        log.debug("Team leaderboard requested: challengeId={}", challengeId);
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
