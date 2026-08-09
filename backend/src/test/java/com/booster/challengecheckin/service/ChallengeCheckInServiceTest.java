package com.booster.challengecheckin.service;

import com.booster.challenge.domain.Challenge;
import com.booster.challenge.domain.ChallengeStatus;
import com.booster.challenge.repository.ChallengeRepository;
import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.domain.CheckInStatus;
import com.booster.challengecheckin.dto.CheckInResponse;
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
import org.springframework.dao.DataIntegrityViolationException;
import java.time.LocalDate;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
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

    // ── 이슈 I1(BS-39): 동시 첫 체크인 경쟁 → 500이 아니라 멱등 복구 ──
    // 예전엔 CheckInInsertHelper가 REQUIRES_NEW 안에서 UNIQUE 위반을 잡아 재조회 →
    // 오염된 세션 flush → AssertionFailure(null id) → 500. (같은 유저 동시 체크인 시 재현)
    // 수정 후: 헬퍼는 삽입만 하고 위반을 전파, 서비스가 바깥(깨끗한) 트랜잭션에서 재조회해 복구.

    @Test
    void recordCheckIn_whenConcurrentInsertRace_shouldRecoverIdempotentlyNot500() {
        ChallengeParticipant participant = confirmedParticipantWithTeam();
        when(participantRepository.findConfirmedByUserAndChallenge(challengeId, userId))
                .thenReturn(Optional.of(participant));

        Challenge challenge = mock(Challenge.class);
        when(challenge.getStatus()).thenReturn(ChallengeStatus.ACTIVE);
        when(challengeRepository.findById(challengeId)).thenReturn(Optional.of(challenge));

        LocalDate today = LocalDate.now(java.time.ZoneId.of("Asia/Seoul"));

        // 경쟁 승자가 이미 오늘자 SUCCESS 레코드를 만든 상태
        ChallengeCheckIn winner = ChallengeCheckIn.builder()
                .participantId(participant.getId())
                .challengeId(challengeId)
                .teamId(participant.getTeamId())
                .checkInDate(today)
                .status(CheckInStatus.SUCCESS)
                .build();

        // step3 첫 조회는 empty(경쟁 시작), catch 재조회는 승자 레코드
        when(checkInRepository.findByParticipantIdAndCheckInDate(any(), eq(today)))
                .thenReturn(Optional.empty(), Optional.of(winner));

        // 동시 첫 삽입 → UNIQUE 위반 (헬퍼는 이제 삼키지 않고 전파)
        when(checkInInsertHelper.insertInNewTransaction(any()))
                .thenThrow(new DataIntegrityViolationException("unique_participant_date"));

        // 수정 후: 예외(500) 없이 멱등 SUCCESS 반환
        CheckInResponse resp = checkInService.recordCheckIn(userId, challengeId, lat, lng);
        assertEquals(CheckInStatus.SUCCESS, resp.getStatus());

        // 헬퍼에 위임 + catch에서 재조회(총 2회) 했는지 확인
        verify(checkInInsertHelper).insertInNewTransaction(any());
        verify(checkInRepository, times(2)).findByParticipantIdAndCheckInDate(any(), eq(today));
    }

    // ── 이슈 I14(BS-39): 체크인 목록 조회 멤버십 검사 ──
    // 예전엔 컨트롤러/서비스 어디에도 검사가 없어 비참여자가 임의 challengeId로 남의 팀 체크인
    // 현황을 조회할 수 있었다(I2 팀채팅 읽기와 동일 계열).

    @Test
    void getTeamCheckIns_whenNotParticipant_shouldThrowUnauthorized() {
        LocalDate date = LocalDate.of(2026, 8, 4);
        when(participantRepository.findConfirmedByUserAndChallenge(challengeId, userId))
                .thenReturn(Optional.empty());

        assertThrows(com.booster.shared.common.UnauthorizedException.class,
                () -> checkInService.getTeamCheckIns(userId, challengeId, date));

        // 멤버십 실패 시 체크인 데이터는 조회하지 않아야 한다(정보노출 차단)
        verify(checkInRepository, never()).findByChallengeIdAndCheckInDate(any(), any());
    }

    @Test
    void getTeamCheckIns_whenParticipant_shouldReturnList() {
        LocalDate date = LocalDate.of(2026, 8, 4);
        when(participantRepository.findConfirmedByUserAndChallenge(challengeId, userId))
                .thenReturn(Optional.of(confirmedParticipantWithTeam()));
        when(checkInRepository.findByChallengeIdAndCheckInDate(challengeId, date))
                .thenReturn(java.util.List.of());

        assertEquals(0, checkInService.getTeamCheckIns(userId, challengeId, date).size());
        verify(checkInRepository).findByChallengeIdAndCheckInDate(challengeId, date);
    }
}
