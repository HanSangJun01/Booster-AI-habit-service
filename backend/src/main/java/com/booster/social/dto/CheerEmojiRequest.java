package com.booster.social.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
public class CheerEmojiRequest {

    @NotNull
    private Long toParticipantId;

    @NotBlank
    private String emojiType;
}
