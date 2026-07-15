package com.booster.social.service;

import com.booster.participant.domain.ChallengeParticipant;
import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.common.BusinessException;
import com.booster.social.domain.CheerEmoji;
import com.booster.social.dto.CheerEmojiResponse;
import com.booster.social.repository.CheerEmojiRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Slf4j
@Service
@Transactional
@RequiredArgsConstructor
public class CheerService {

    private final CheerEmojiRepository cheerEmojiRepository;
    private final ChallengeParticipantRepository participantRepository;

    /**
     * @param fromUserId 응원 보내는 사람의 userId (JWT principal). 챌린지 참여자 participantId로 해석된다.
     * @param toParticipantId 응원 받는 사람의 participantId (같은 챌린지 참여자여야 함).
     *
     * <p>[BS-A/B 통합 수정] 이전에는 컨트롤러가 userId를 fromParticipantId로 넘겨 from(userId 공간)과
     * to(participantId 공간)가 뒤섞였다. self-cheer 검증이 서로 다른 ID 공간을 비교해 무력화되고
     * 멤버십 검증도 없었다. 이제 fromUserId를 CONFIRMED 참여자로 해석하고, to도 같은 챌린지
     * 참여자인지 검증한 뒤, 두 participantId를 비교해 self-cheer를 막는다(chat 경로와 동일한 정책).
     */
    public CheerEmojiResponse sendCheer(Long challengeId, Long fromUserId,
                                        Long toParticipantId, String emojiType) {
        ChallengeParticipant from = participantRepository
                .findConfirmedByUserAndChallenge(challengeId, fromUserId)
                .orElseThrow(() -> {
                    log.warn("Non-participant cheer attempt: userId={}, challengeId={}", fromUserId, challengeId);
                    return BusinessException.forbidden(
                            "NOT_A_PARTICIPANT", "챌린지 참여자만 응원할 수 있습니다.");
                });

        ChallengeParticipant to = participantRepository.findById(toParticipantId)
                .filter(p -> p.getChallenge().getId().equals(challengeId))
                .orElseThrow(() -> BusinessException.badRequest(
                        "INVALID_CHEER_TARGET", "대상이 이 챌린지의 참여자가 아닙니다."));

        if (from.getId().equals(to.getId())) {
            log.warn("Self-cheer attempted: participantId={}", from.getId());
            throw BusinessException.badRequest("SELF_CHEER", "자기 자신에게는 응원할 수 없습니다.");
        }

        CheerEmoji emoji = CheerEmoji.builder()
                .challengeId(challengeId)
                .fromParticipantId(from.getId())
                .toParticipantId(to.getId())
                .emojiType(emojiType)
                .build();

        CheerEmojiResponse response = CheerEmojiResponse.from(cheerEmojiRepository.save(emoji));
        log.info("Cheer sent: fromParticipantId={}, toParticipantId={}", from.getId(), to.getId());
        return response;
    }

    @Transactional(readOnly = true)
    public List<CheerEmojiResponse> getCheersByChallenge(Long challengeId) {
        return cheerEmojiRepository.findByChallengeId(challengeId).stream()
                .map(CheerEmojiResponse::from)
                .toList();
    }
}
