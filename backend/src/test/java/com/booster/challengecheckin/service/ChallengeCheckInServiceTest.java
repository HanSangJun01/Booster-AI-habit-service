package com.booster.challengecheckin.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.domain.CheckInStatus;
import com.booster.challengecheckin.repository.ChallengeCheckInRepository;
import com.booster.challengecheckin.repository.GpsVerificationResultRepository;
import com.booster.challengecheckin.repository.VerificationDecisionRepository;
import com.booster.challengecheckin.repository.VerificationSubmissionRepository;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.domain.ParticipantStatus;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.gps.GpsVerificationEvaluator;
import com.booster.team.repository.TeamRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import java.time.LocalDate;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ChallengeCheckInServiceTest {

    @Mock
    private ChallengeCheckInRepository checkInRepository;

    @Mock
    private ChallengeParticipantRepository participantRepository;

    @Mock
    private TeamRepository teamRepository;

    @Mock
    private GpsVerificationEvaluator gpsVerificationEvaluator;

    @Mock
    private VerificationSubmissionRepository submissionRepository;

    @Mock
    private GpsVerificationResultRepository gpsResultRepository;

    @Mock
    private VerificationDecisionRepository decisionRepository;

    @Mock
    private ChallengeRepository challengeRepository;

    @Mock
    private CheckInInsertHelper checkInInsertHelper;

    @InjectMocks
    private ChallengeCheckInService checkInService;

    private final Long userId = 1L;
    private final Long challengeId = 10L;
    private final double lat = 37.5;
    private final double lng = 127.0;

    private ChallengeParticipant confirmedParticipant() {
        return ChallengeParticipant.builder()
                .challenge(mock(com.booster.challenge.domain.Challenge.class))
                .userId(userId)
                .status(ParticipantStatus.CONFIRMED)
                .gpsLat(lat)
                .gpsLng(lng)
                .gpsRadiusMeters(100)
                .gpsLocked(true)
                .build(); // teamId = null
    }

    private ChallengeParticipant confirmedParticipantWithTeam() {
        return ChallengeParticipant.builder()
                .challenge(mock(com.booster.challenge.domain.Challenge.class))
                .userId(userId)
                .teamId(5L)
                .status(ParticipantStatus.CONFIRMED)
                .gpsLat(lat)
                .gpsLng(lng)
                .gpsRadiusMeters(100)
                .gpsLocked(true)
                .build();
    }

    // ── 재현 테스트: teamId가 null인 참여자는 체크인 불가 ──

    @Test
    void recordCheckIn_whenParticipantHasNoTeam_shouldThrowIllegalStateException() {
        // given: teamId = null인 참여자 (팀 배정 안 된 상태)
        ChallengeParticipant participant = confirmedParticipant(); // teamId = null
        when(participantRepository.findConfirmedByUserAndChallenge(challengeId, userId))
                .thenReturn(Optional.of(participant));

        Challenge challenge = mock(Challenge.class);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.ACTIVE);
        when(challengeRepository.findById(challengeId)).thenReturn(Optional.of(challenge));

        // 수정 전: teamId=null 그대로 저장 성공 → 정산에서 누락
        // 수정 후: IllegalStateException 발생
        assertThrows(IllegalStateException.class,
                () -> checkInService.recordCheckIn(userId, challengeId, lat, lng));
    }

    // ── 이슈 4: recordCheckIn - 챌린지 ENDED 상태일 때 IllegalStateException 기대 ──

    @Test
    void recordCheckIn_whenChallengeIsEnded_shouldThrowIllegalStateException() {
        ChallengeParticipant participant = confirmedParticipant();
        when(participantRepository.findConfirmedByUserAndChallenge(challengeId, userId))
                .thenReturn(Optional.of(participant));

        Challenge challenge = mock(Challenge.class);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.ENDED);
        when(challengeRepository.findById(challengeId)).thenReturn(Optional.of(challenge));

        assertThrows(IllegalStateException.class,
                () -> checkInService.recordCheckIn(userId, challengeId, lat, lng));
    }

    @Test
    void recordCheckIn_whenChallengeIsReady_shouldThrowIllegalStateException() {
        ChallengeParticipant participant = confirmedParticipant();
        when(participantRepository.findConfirmedByUserAndChallenge(challengeId, userId))
                .thenReturn(Optional.of(participant));

        Challenge challenge = mock(Challenge.class);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.READY);
        when(challengeRepository.findById(challengeId)).thenReturn(Optional.of(challenge));

        assertThrows(IllegalStateException.class,
                () -> checkInService.recordCheckIn(userId, challengeId, lat, lng));
    }

    // ── 이슈 5: recordCheckIn - 동시 중복 insert 시 CheckInInsertHelper에 위임 ──

    @Test
    void recordCheckIn_whenDuplicateInsert_shouldDelegateToHelperAndPropagateConflict() {
        ChallengeParticipant participant = confirmedParticipantWithTeam();
        when(participantRepository.findConfirmedByUserAndChallenge(challengeId, userId))
                .thenReturn(Optional.of(participant));

        Challenge challenge = mock(Challenge.class);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.ACTIVE);
        when(challengeRepository.findById(challengeId)).thenReturn(Optional.of(challenge));

        LocalDate today = LocalDate.now(java.time.ZoneId.of("Asia/Seoul"));

        // 처음 조회 시 existing 없음 → insertOrFetch 호출됨
        when(checkInRepository.findByParticipantIdAndCheckInDate(any(), eq(today)))
                .thenReturn(Optional.empty());

        // helper가 해결 불가한 충돌 상황 시뮬레이션
        when(checkInInsertHelper.insertOrFetch(any(), any(), any()))
                .thenThrow(new IllegalStateException("Check-in conflict unresolvable"));

        // DataIntegrityViolationException(rollback-only → 500) 대신 IllegalStateException으로 전파
        assertThrows(IllegalStateException.class,
                () -> checkInService.recordCheckIn(userId, challengeId, lat, lng));

        // save가 서비스에서 직접 호출되지 않고 helper에 위임됨을 확인
        verify(checkInInsertHelper).insertOrFetch(any(), eq(participant.getId()), eq(today));
        verify(checkInRepository, never()).save(any(ChallengeCheckIn.class));
    }
}
