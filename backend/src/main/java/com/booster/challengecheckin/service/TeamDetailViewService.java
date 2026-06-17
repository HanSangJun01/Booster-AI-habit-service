package com.booster.challengecheckin.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.domain.CheckInStatus;
import com.booster.challengecheckin.dto.TeamDetailResponse;
import com.booster.challengecheckin.dto.TeamDetailResponse.TeamInfo;
import com.booster.challengecheckin.dto.TeamMemberCheckInStatus;
import com.booster.challengecheckin.repository.ChallengeCheckInRepository;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.common.ResourceNotFoundException;
import com.booster.team.domain.Team;
import com.booster.team.repository.TeamRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class TeamDetailViewService {

    private final TeamRepository teamRepository;
    private final ChallengeParticipantRepository participantRepository;
    private final ChallengeCheckInRepository checkInRepository;
    private final ParticipationRateCalculator participationRateCalculator;
    private final ChallengeRepository challengeRepository;

    public TeamDetailResponse getTeamComparison(Long challengeId, Long userId) {
        // 1. 챌린지 조회
        Challenge challenge = challengeRepository.findById(challengeId)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge", challengeId));

        // 2. 사용자 participant 조회하여 myTeamId 확인
        ChallengeParticipant myParticipant = participantRepository
                .findConfirmedByUserAndChallenge(challengeId, userId)
                .orElseThrow(() -> new ResourceNotFoundException(
                        "ChallengeParticipant not found for userId=" + userId + ", challengeId=" + challengeId));
        Long myTeamId = myParticipant.getTeamId();

        // 3. 챌린지의 팀 2개 조회
        List<Team> teams = teamRepository.findByChallengeId(challengeId);
        Team myTeam = teams.stream()
                .filter(t -> t.getId().equals(myTeamId))
                .findFirst()
                .orElseThrow(() -> new ResourceNotFoundException("Team", myTeamId));
        Team opponentTeam = teams.stream()
                .filter(t -> !t.getId().equals(myTeamId))
                .findFirst()
                .orElseThrow(() -> new ResourceNotFoundException(
                        "Opponent team not found for challengeId=" + challengeId));

        // 4. 오늘 날짜 (KST)
        LocalDate today = LocalDate.now(ZoneId.of("Asia/Seoul"));

        // 5. challengeDay 계산
        Integer challengeDay = null;
        if (challenge.getStartedAt() != null) {
            long days = ChronoUnit.DAYS.between(challenge.getStartedAt().toLocalDate(), today);
            challengeDay = (int) days + 1;
        }

        // 6. 각 팀 정보 구성
        TeamInfo myTeamInfo = buildTeamInfo(myTeam, today);
        TeamInfo opponentTeamInfo = buildTeamInfo(opponentTeam, today);

        return TeamDetailResponse.builder()
                .myTeam(myTeamInfo)
                .opponentTeam(opponentTeamInfo)
                .challengeDay(challengeDay)
                .totalDays(challenge.getDurationDays())
                .today(today)
                .build();
    }

    private TeamInfo buildTeamInfo(Team team, LocalDate today) {
        List<ChallengeParticipant> participants = participantRepository.findByTeamId(team.getId());
        List<ChallengeCheckIn> todayCheckIns = checkInRepository.findByTeamIdAndCheckInDate(team.getId(), today);

        // participantId -> checkIn 맵
        Map<Long, ChallengeCheckIn> checkInByParticipantId = todayCheckIns.stream()
                .collect(Collectors.toMap(ChallengeCheckIn::getParticipantId, c -> c, (a, b) -> a));

        List<TeamMemberCheckInStatus> members = participants.stream()
                .map(p -> {
                    ChallengeCheckIn checkIn = checkInByParticipantId.get(p.getId());
                    boolean checkedIn = checkIn != null && checkIn.getStatus() == CheckInStatus.SUCCESS;
                    return TeamMemberCheckInStatus.builder()
                            .userId(p.getUserId())
                            .participantId(p.getId())
                            .checkedIn(checkedIn)
                            .status(checkIn != null ? checkIn.getStatus() : null)
                            .build();
                })
                .toList();

        int todayCheckedInCount = (int) members.stream().filter(TeamMemberCheckInStatus::isCheckedIn).count();

        return new TeamInfo(
                team.getId(),
                team.getName(),
                participationRateCalculator.currentRate(team.getId()),
                todayCheckedInCount,
                participants.size(),
                members
        );
    }
}
