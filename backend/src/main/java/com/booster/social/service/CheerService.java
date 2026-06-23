package com.booster.social.service;

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

    public CheerEmojiResponse sendCheer(Long challengeId, Long fromParticipantId,
                                        Long toParticipantId, String emojiType) {
        if (fromParticipantId.equals(toParticipantId)) {
            log.warn("Self-cheer attempted: participantId={}", fromParticipantId);
            throw new IllegalArgumentException("Cannot send cheer to yourself");
        }

        CheerEmoji emoji = CheerEmoji.builder()
                .challengeId(challengeId)
                .fromParticipantId(fromParticipantId)
                .toParticipantId(toParticipantId)
                .emojiType(emojiType)
                .build();

        CheerEmojiResponse response = CheerEmojiResponse.from(cheerEmojiRepository.save(emoji));
        log.info("Cheer sent: fromParticipantId={}, toParticipantId={}", fromParticipantId, toParticipantId);
        return response;
    }

    @Transactional(readOnly = true)
    public List<CheerEmojiResponse> getCheersByChallenge(Long challengeId) {
        return cheerEmojiRepository.findByChallengeId(challengeId).stream()
                .map(CheerEmojiResponse::from)
                .toList();
    }
}
