package com.booster.social.service;

import com.booster.challenge.domain.Challenge;
import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.common.BusinessException;
import com.booster.social.domain.CheerEmoji;
import com.booster.social.repository.CheerEmojiRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * [BS-A/B 통합] cheer의 from(userId)·to(participantId) 신원 혼용 수정 회귀 테스트.
 * 통합 전 결함: 컨트롤러가 JWT userId를 fromParticipantId로 넘겨 self-cheer 검증이 무력화되고
 * 멤버십 검증이 없었다. 수정 후: fromUserId를 CONFIRMED 참여자로 해석, to도 같은 챌린지 참여자인지
 * 검증, participantId 공간에서 self-cheer를 막는다.
 */
@ExtendWith(MockitoExtension.class)
class CheerServiceTest {

    @Mock private CheerEmojiRepository cheerEmojiRepository;
    @Mock private ChallengeParticipantRepository participantRepository;

    @InjectMocks
    private CheerService cheerService;

    private static final Long CHALLENGE_ID = 42L;
    private static final Long FROM_USER_ID = 7L;
    private static final Long FROM_PARTICIPANT_ID = 100L;
    private static final Long TO_PARTICIPANT_ID = 101L;

    private ChallengeParticipant participant(Long participantId, Long challengeId) {
        ChallengeParticipant p = mock(ChallengeParticipant.class);
        lenient().when(p.getId()).thenReturn(participantId);
        Challenge c = mock(Challenge.class);
        lenient().when(c.getId()).thenReturn(challengeId);
        lenient().when(p.getChallenge()).thenReturn(c);
        return p;
    }

    @Test
    void sendCheer_happyPath_savesParticipantIdSpace() {
        // 목은 스터빙 밖에서 먼저 만든다(중첩 stubbing → UnfinishedStubbingException 회피)
        ChallengeParticipant from = participant(FROM_PARTICIPANT_ID, CHALLENGE_ID);
        ChallengeParticipant to = participant(TO_PARTICIPANT_ID, CHALLENGE_ID);
        when(participantRepository.findConfirmedByUserAndChallenge(CHALLENGE_ID, FROM_USER_ID))
                .thenReturn(Optional.of(from));
        when(participantRepository.findById(TO_PARTICIPANT_ID))
                .thenReturn(Optional.of(to));
        when(cheerEmojiRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        cheerService.sendCheer(CHALLENGE_ID, FROM_USER_ID, TO_PARTICIPANT_ID, "CLAP");

        ArgumentCaptor<CheerEmoji> saved = ArgumentCaptor.forClass(CheerEmoji.class);
        verify(cheerEmojiRepository).save(saved.capture());
        // from은 userId(7)가 아니라 caller의 participantId(100)로 저장되어야 한다
        assertEquals(FROM_PARTICIPANT_ID, saved.getValue().getFromParticipantId());
        assertEquals(TO_PARTICIPANT_ID, saved.getValue().getToParticipantId());
        assertEquals(CHALLENGE_ID, saved.getValue().getChallengeId());
    }

    @Test
    void sendCheer_whenCallerNotParticipant_throwsForbidden() {
        when(participantRepository.findConfirmedByUserAndChallenge(CHALLENGE_ID, FROM_USER_ID))
                .thenReturn(Optional.empty());

        BusinessException ex = assertThrows(BusinessException.class, () ->
                cheerService.sendCheer(CHALLENGE_ID, FROM_USER_ID, TO_PARTICIPANT_ID, "CLAP"));
        assertEquals(HttpStatus.FORBIDDEN, ex.getStatus());
        verify(cheerEmojiRepository, never()).save(any());
    }

    @Test
    void sendCheer_whenTargetInAnotherChallenge_throwsBadRequest() {
        ChallengeParticipant from = participant(FROM_PARTICIPANT_ID, CHALLENGE_ID);
        ChallengeParticipant to = participant(TO_PARTICIPANT_ID, 99L); // 다른 챌린지 소속 → filter 탈락
        when(participantRepository.findConfirmedByUserAndChallenge(CHALLENGE_ID, FROM_USER_ID))
                .thenReturn(Optional.of(from));
        when(participantRepository.findById(TO_PARTICIPANT_ID))
                .thenReturn(Optional.of(to));

        BusinessException ex = assertThrows(BusinessException.class, () ->
                cheerService.sendCheer(CHALLENGE_ID, FROM_USER_ID, TO_PARTICIPANT_ID, "CLAP"));
        assertEquals(HttpStatus.BAD_REQUEST, ex.getStatus());
        verify(cheerEmojiRepository, never()).save(any());
    }

    @Test
    void sendCheer_selfCheer_blockedInParticipantIdSpace() {
        // caller의 participantId == 대상 participantId (자기 자신)
        ChallengeParticipant from = participant(FROM_PARTICIPANT_ID, CHALLENGE_ID);
        ChallengeParticipant self = participant(FROM_PARTICIPANT_ID, CHALLENGE_ID);
        when(participantRepository.findConfirmedByUserAndChallenge(CHALLENGE_ID, FROM_USER_ID))
                .thenReturn(Optional.of(from));
        when(participantRepository.findById(FROM_PARTICIPANT_ID))
                .thenReturn(Optional.of(self));

        BusinessException ex = assertThrows(BusinessException.class, () ->
                cheerService.sendCheer(CHALLENGE_ID, FROM_USER_ID, FROM_PARTICIPANT_ID, "CLAP"));
        assertEquals(HttpStatus.BAD_REQUEST, ex.getStatus());
        assertEquals("SELF_CHEER", ex.getCode());
        verify(cheerEmojiRepository, never()).save(any());
    }
}
