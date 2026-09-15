package com.booster.social.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
public class CheerEmojiRequest {

    @NotNull
    private Long toParticipantId;

    /** DB 컬럼이 VARCHAR(50)이다. 막지 않으면 넘치는 값이 INSERT 에서 터져 409 "충돌"로 잘못 응답됐다. */
    @NotBlank
    @Size(max = 50)
    private String emojiType;
}
