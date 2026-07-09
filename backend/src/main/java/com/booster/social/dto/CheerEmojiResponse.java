package com.booster.social.dto;

import com.booster.social.domain.CheerEmoji;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@Builder
public class CheerEmojiResponse {

    private Long id;
    private Long challengeId;
    private Long fromParticipantId;
    private Long toParticipantId;
    private String emojiType;
    private LocalDateTime createdAt;

    public static CheerEmojiResponse from(CheerEmoji e) {
        return CheerEmojiResponse.builder()
                .id(e.getId())
                .challengeId(e.getChallengeId())
                .fromParticipantId(e.getFromParticipantId())
                .toParticipantId(e.getToParticipantId())
                .emojiType(e.getEmojiType())
                .createdAt(e.getCreatedAt())
                .build();
    }
}
